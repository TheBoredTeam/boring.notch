/**
 * pi-sidecar — a self-contained bridge between boring.notch (Swift) and the Pi
 * coding agent. Speaks newline-delimited JSON on stdin/stdout:
 *
 *   stdin   {"type":"prompt","text":"…"}   {"type":"abort"}   {"type":"set_model","id":"…"}
 *           {"type":"list_connections"}   {"type":"reconnect","connectedAccountId":"ca_…"}
 *           {"type":"connect","toolkit":"gmail","alias":"work"}
 *           {"type":"set_default","toolkit":"gmail","selector":"work"}  // "" → Automatic
 *           {"type":"rename_connection","connectedAccountId":"ca_…","alias":"work"}  // "" → clear
 *           {"type":"delete_connection","connectedAccountId":"ca_…"}
 *   stdout  {"type":"status","word":"thinking"}
 *           {"type":"tool_forming","index":0,"tool":"GMAIL_SEND_EMAIL","toolkit":"gmail",
 *            "logo":"https://logos.composio.dev/api/gmail"}   // tool/toolkit/logo null until known
 *           {"type":"tool_start","id":"t1","tool":"GMAIL_SEND_EMAIL","word":"gmail",
 *            "toolkit":"gmail","logo":"https://logos.composio.dev/api/gmail"}
 *           {"type":"tool_end","id":"t1","ok":true}
 *           {"type":"text_delta","delta":"Done — …"}
 *           {"type":"error","message":"…"}
 *           {"type":"done"}
 *           // connection management (Composio v3 SDK):
 *           {"type":"connections","items":[{"toolkit":"gmail","alias":"work",
 *            "connectedAccountId":"ca_…","authConfigId":"ac_…","status":"ACTIVE",
 *            "logo":"https://…"}],   // logo resolved from Composio toolkit metadata
 *            "defaults":{"gmail":"work"}}   // defaults = file-sourced default account/toolkit
 *           {"type":"connection_expired","toolkit":"gmail","alias":"work",
 *            "connectedAccountId":"ca_…","userId":"…","status":"EXPIRED"}
 *           {"type":"connection_link","url":"https://…","toolkit":"gmail"}
 *
 * It reuses the user's pi/composio CLI login by inheriting HOME (so ~/.pi and
 * ~/.composio resolve). The Composio × Pi extension is auto-loaded by pi from the
 * user's `packages` setting in ~/.pi/agent/settings.json.
 *
 * Conversation lifecycle: one in-memory session carries context across prompts,
 * but it expires after IDLE_RESET_MS without a prompt following the last
 * response — the next prompt then starts a fresh thread instead of dragging
 * hours of stale context (and its token cost) along.
 */

import {
    createAgentSession,
    DefaultResourceLoader,
    getAgentDir,
    SessionManager,
    SettingsManager,
} from "@earendil-works/pi-coding-agent";
import { Composio } from "@composio/core";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

// The pi agent directory (~/.pi/agent). Resolved once at module load so both the
// session builder and the default-account config store can use it. (Previously
// computed inside ensureSession(); hoisted so dispatch() can reach it.)
const agentDir = getAgentDir();

/**
 * Appended to pi's system prompt. Prompts from the notch are one-shot commands
 * fired from a tiny panel — not a chat — so the agent must act, never interview.
 */
const NOTCH_SYSTEM_PROMPT = `
## boring.notch execution context

You are running inside boring.notch, a small macOS notch utility. Each user prompt is a
one-shot command, not the start of a conversation:

- NEVER ask clarifying questions or present options — there is no back-and-forth. Pick the
  most reasonable interpretation and execute it fully.
- Use your tools to complete the task end-to-end in this single turn.
- You have a remote workbench: a remote bash shell and remote workbench/sandbox tools.
  Use them whenever they help — running commands, scripts, file/data work, fetching or
  transforming things, or anything a shell does better than reasoning alone. Prefer the
  remote bash / workbench over guessing; reach for them proactively when a task is
  shell-shaped, and report the concrete result.
- For Composio tools: use only ACTIVE connected accounts. When a default account is
  listed for a toolkit below, pass that account; otherwise use the most recently
  connected ACTIVE account. Never use EXPIRED/INITIALIZING accounts.
- When the user explicitly asks for a link — a connection/authorization URL, a page or
  resource URL, or any other link — provide it directly as ordinary markdown so it
  renders as a tappable link. Never withhold a link the user asked for.
- Do NOT spontaneously paste authorization URLs the user did not ask for. If a toolkit
  has no ACTIVE account and the user did not request a connect link, do what you can and
  briefly note "connect <app> from the Composio menu-bar app" (one short sentence) —
  reconnection is handled out of band by the host app.
- Keep the final reply short: what was done and the key result. No "let me know if…"
  closers, no follow-up questions.
`.trim();

// stdout is our protocol channel — keep it pure. Route any stray library logging
// to stderr so it can't corrupt a JSON line.
const stdoutWrite = process.stdout.write.bind(process.stdout);
function emit(obj: unknown): void {
    stdoutWrite(JSON.stringify(obj) + "\n");
}

// The agent fires thinking_delta on nearly every token; collapse consecutive
// identical status words so the wire stays readable.
let lastStatusWord: string | null = null;
function emitStatus(word: string): void {
    if (word === lastStatusWord) return;
    lastStatusWord = word;
    emit({ type: "status", word });
}
const toErr = (...args: unknown[]) =>
    process.stderr.write(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" ") + "\n");
console.log = toErr as typeof console.log;
console.info = toErr as typeof console.info;
console.warn = toErr as typeof console.warn;
console.debug = toErr as typeof console.debug;

/**
 * Composio tool names look like `GMAIL_SEND_EMAIL` / `GOOGLECALENDAR_FIND_EVENT`.
 * The toolkit slug is the lowercased prefix before the first underscore, which is
 * also the key the Composio logo CDN expects (`gmail`, `googlecalendar`).
 */
function toolkitSlug(toolName: string): string {
    const prefix = (toolName.split("_")[0] || toolName).trim();
    return prefix.toLowerCase();
}

/**
 * Composio routes some calls through the meta-tool `composio_execute_tool`, whose
 * own slug is just `composio` — so without unwrapping, the notch would show the
 * generic Composio mark even while Gmail/Calendar/etc. is the real app at work.
 *
 * The execute payload carries the underlying action as a `*_*` slug. Pull it out
 * (the exact key varies across Composio versions, so try the known aliases) and
 * return it so the caller can drive the real toolkit's logo/color and a pretty
 * action name. `composio_search_tools` / `composio_get_tool_schemas` are genuine
 * meta-ops and are intentionally left as `composio`.
 */
function unwrapComposioAction(toolName: string, args: any): string | null {
    if (toolName !== "composio_execute_tool") return null;
    const candidate =
        args?.tool_slug ?? args?.toolSlug ?? args?.slug ?? args?.tool ?? args?.action ?? args?.action_name;
    if (typeof candidate === "string" && candidate.includes("_")) {
        return candidate;
    }
    return null;
}

/**
 * A tool call the model is still streaming arguments for. Tracked per
 * `contentIndex` so the notch can show "Calling a tool…" the instant the model
 * commits to a call — seconds before `tool_execution_start` fires — and upgrade
 * to the real name/toolkit as soon as either becomes readable.
 */
interface FormingTool {
    tool: string | null;
    toolkit: string | null;
}

// ── Composio connection management ──────────────────────────────────────────
// The in-notch "Connect" CTA is gone. Instead this background service tracks
// connected-account health and surfaces re-auth out of band: it talks to the
// Composio v3 SDK directly (the pi extension only exposes *tools*, not account
// management). Everything here is best-effort — if no API key resolves, the
// agent still runs and connection features simply stay dormant.

// Which Composio user the notch's connected accounts live under. The pi-composio
// extension scopes accounts by user id; set COMPOSIO_USER_ID to match it.
// TODO(boring.notch): confirm the exact user id the extension uses on the host.
const COMPOSIO_USER_ID = process.env.COMPOSIO_USER_ID?.trim() || "default";

// Account statuses that mean "unusable until the user re-authorizes".
const REAUTH_STATUSES = new Set(["EXPIRED", "INACTIVE", "REVOKED", "FAILED"]);

// ── Default-account config store ────────────────────────────────────────────
// The single source of truth for "default account per toolkit" is the Composio×Pi
// extension's own config file — the only store the agent's resolver actually reads
// (`~/composio-x-pi/src/lib/account-resolver.ts` → `readStoredComposioConfig`). We
// MIRROR that file's reader/writer here so the two writers never corrupt each other:
// always read-merge-write (preserving `apiKey` and any other keys), write the
// `defaultAccounts` map keyed by lowercased toolkit slug, mode 0o600 + trailing
// newline. The system prompt is also sourced from this file, so UI and agent can
// never drift. (Mirror of `~/composio-x-pi/src/config-store.ts`.)
const composioConfigPath = join(agentDir, "extensions", "composio-x-pi.json");

interface StoredComposioConfig {
    apiKey?: string;
    defaultAccounts?: Record<string, string>;
    [key: string]: unknown;
}

/** Read the extension config raw, preserving every key (apiKey, …). `{}` if absent/bad. */
function readStoredComposioConfig(): StoredComposioConfig {
    try {
        const parsed = JSON.parse(readFileSync(composioConfigPath, "utf8"));
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
        return parsed as StoredComposioConfig;
    } catch {
        return {};
    }
}

/** The `defaultAccounts` map (lowercased slug → selector), sanitized; `{}` if none. */
function readDefaultAccounts(): Record<string, string> {
    const accounts = readStoredComposioConfig().defaultAccounts;
    if (!accounts || typeof accounts !== "object") return {};
    return Object.fromEntries(
        Object.entries(accounts)
            .filter(([k, v]) => k && typeof v === "string" && (v as string).trim())
            .map(([k, v]) => [k.trim().toLowerCase(), (v as string).trim()]),
    );
}

/**
 * Set (or, with an empty selector, clear → "Automatic") the default account for a
 * toolkit. Read-merge-write so `apiKey` and any unknown keys survive untouched —
 * a blind overwrite would wipe the agent's stored key and break auth.
 */
function writeDefaultAccount(toolkit: string, selector: string): void {
    const slug = toolkit.trim().toLowerCase();
    if (!slug) return;
    const current = readStoredComposioConfig();
    const defaults: Record<string, string> = { ...(current.defaultAccounts ?? {}) };
    const trimmed = selector.trim();
    if (trimmed) {
        defaults[slug] = trimmed;
    } else {
        delete defaults[slug];
    }
    const next: StoredComposioConfig = { ...current };
    if (Object.keys(defaults).length > 0) {
        next.defaultAccounts = defaults;
    } else {
        delete next.defaultAccounts;
    }
    try {
        mkdirSync(dirname(composioConfigPath), { recursive: true });
        writeFileSync(composioConfigPath, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
    } catch (e: any) {
        toErr("composio: write default account failed:", String(e?.message ?? e));
    }
}

interface ConnectionItem {
    toolkit: string;
    alias: string | null;
    wordId: string | null; // Composio's human word id (selector fallback after alias)
    connectedAccountId: string;
    authConfigId: string | null;
    status: string;
    logo: string | null; // resolved from Composio toolkit metadata (meta.logo)
}

// Last-seen accounts, so `reconnect` can resolve an authConfig without a second
// round-trip and map a toolkit → its account.
let lastConnections: ConnectionItem[] = [];

// Toolkit logo URLs resolved from Composio metadata (`toolkits.get(slug).meta.logo`),
// cached per slug so a reconcile doesn't refetch. `null` = looked up, none available.
const toolkitLogoCache = new Map<string, string | null>();

/** Resolve a toolkit's brand logo URL from Composio metadata (cached). */
async function resolveToolkitLogo(slug: string): Promise<string | null> {
    if (!slug) return null;
    if (toolkitLogoCache.has(slug)) return toolkitLogoCache.get(slug) ?? null;
    const composio = getComposio();
    if (!composio) return null;
    try {
        const tk: any = await (composio as any).toolkits.get(slug);
        const logo = typeof tk?.meta?.logo === "string" && tk.meta.logo ? tk.meta.logo : null;
        toolkitLogoCache.set(slug, logo);
        return logo;
    } catch (e: any) {
        toErr("composio: toolkit logo lookup failed for", slug, ":", String(e?.message ?? e));
        toolkitLogoCache.set(slug, null); // don't hammer the API for a slug that errored
        return null;
    }
}

function resolveComposioApiKey(): string | null {
    const env = process.env.COMPOSIO_API_KEY?.trim();
    if (env) return env;
    // Fall back to the CLI's stored credentials (best-effort; layout varies by version).
    for (const rel of ["user_data.json", "credentials.json"]) {
        try {
            const json = JSON.parse(readFileSync(join(homedir(), ".composio", rel), "utf8"));
            const key = json?.api_key ?? json?.apiKey ?? json?.COMPOSIO_API_KEY;
            if (typeof key === "string" && key) return key;
        } catch {
            /* not present — try next */
        }
    }
    // Last resort, and the most important one for GUI launches: the extension config
    // file (~/.pi/agent/extensions/composio-x-pi.json) — the canonical store the agent
    // itself resolves its key from. When launched from /Applications the sidecar does
    // NOT inherit the shell's COMPOSIO_API_KEY export, so this is the only place the key
    // is found; without it, connection management silently stays dormant (empty list).
    const stored = readStoredComposioConfig().apiKey;
    if (typeof stored === "string" && stored.trim()) return stored.trim();
    return null;
}

let composioClient: Composio | null | undefined; // undefined = not yet attempted
function getComposio(): Composio | null {
    if (composioClient !== undefined) return composioClient;
    const apiKey = resolveComposioApiKey();
    if (!apiKey) {
        toErr("composio: no API key (set COMPOSIO_API_KEY) — connection management disabled");
        composioClient = null;
        return null;
    }
    try {
        composioClient = new Composio({ apiKey });
    } catch (e: any) {
        toErr("composio: client init failed:", String(e?.message ?? e));
        composioClient = null;
    }
    return composioClient;
}

/** List the user's connected accounts, emit them, and flag any that need re-auth. */
async function reconcileConnections(): Promise<void> {
    const composio = getComposio();
    if (!composio) return;
    try {
        const res = await composio.connectedAccounts.list({ userIds: [COMPOSIO_USER_ID] });
        const items: ConnectionItem[] = (res.items ?? []).map((a: any) => ({
            toolkit: String(a.toolkit?.slug ?? "").toLowerCase(),
            alias: a.alias ?? null,
            wordId: a.wordId ?? null,
            connectedAccountId: a.id,
            authConfigId: a.authConfig?.id ?? null,
            status: String(a.status ?? "").toUpperCase(),
            logo: null,
        }));
        // Resolve each distinct toolkit's logo from Composio metadata (cached), then
        // attach it so the menu-bar UI renders real brand marks instead of guessing a URL.
        const slugs = [...new Set(items.map((i) => i.toolkit).filter(Boolean))];
        const logoBySlug = new Map<string, string | null>();
        await Promise.all(slugs.map(async (s) => logoBySlug.set(s, await resolveToolkitLogo(s))));
        for (const it of items) it.logo = logoBySlug.get(it.toolkit) ?? null;
        lastConnections = items;
        // Ship the file-sourced defaults alongside the inventory so the Swift UI loads
        // its ★ state from the same store the agent resolves from — never from UserDefaults.
        emit({ type: "connections", items, defaults: readDefaultAccounts() });
        for (const it of items) {
            if (REAUTH_STATUSES.has(it.status)) {
                emit({
                    type: "connection_expired",
                    toolkit: it.toolkit,
                    alias: it.alias ?? undefined,
                    connectedAccountId: it.connectedAccountId,
                    userId: COMPOSIO_USER_ID,
                    status: it.status,
                });
            }
        }
    } catch (e: any) {
        toErr("composio: list connections failed:", String(e?.message ?? e));
    }
}

/** Kick off a hosted re-auth for a toolkit/account; emit the URL for the host to open. */
async function reconnectAccount(opts: { connectedAccountId?: string; toolkit?: string }): Promise<void> {
    const composio = getComposio();
    if (!composio) return;
    const match = lastConnections.find(
        (c) =>
            (opts.connectedAccountId && c.connectedAccountId === opts.connectedAccountId) ||
            (opts.toolkit && c.toolkit === opts.toolkit.toLowerCase()),
    );
    if (!match?.authConfigId) {
        toErr("composio: reconnect — no authConfig for", JSON.stringify(opts));
        return;
    }
    try {
        const request = await composio.connectedAccounts.link(COMPOSIO_USER_ID, match.authConfigId, {
            alias: match.alias ?? undefined,
            // The account we're re-authing still EXISTS under this auth config (it's
            // EXPIRED/REVOKED/INACTIVE, not gone), so `link()` throws
            // ComposioMultipleConnectedAccountsError without this flag — the same throw
            // the connect path guards against. That silent throw is exactly why the
            // Reconnect button did nothing: no redirectUrl, no `connection_link`, no
            // browser. Allowing multiple lets re-auth proceed; completing the hosted flow
            // refreshes the account and the next reconcile drops it from `reauthNeeded`.
            allowMultiple: true,
        });
        const url = (request as any).redirectUrl;
        if (typeof url === "string" && url) {
            emit({ type: "connection_link", url, toolkit: match.toolkit });
        } else {
            toErr("composio: reconnect — link returned no redirectUrl");
        }
    } catch (e: any) {
        toErr("composio: reconnect failed:", String(e?.message ?? e));
    }
}

/**
 * Set (or, with an empty string, clear) the human-readable alias for a connected
 * account, then re-list so the UI relabels the row. The alias is what the menu-bar
 * shows ("work"/"personal") and a valid default selector — accounts connected via the
 * CLI or the agent arrive without one, so this is the path that actually labels them.
 */
async function renameAccount(connectedAccountId: string, alias: string): Promise<void> {
    const composio = getComposio();
    if (!composio) return;
    try {
        // Empty string is the documented "clear the alias" sentinel for `update`.
        await (composio as any).connectedAccounts.update(connectedAccountId, { alias });
    } catch (e: any) {
        toErr("composio: rename connection failed:", String(e?.message ?? e));
    }
    void reconcileConnections();
}

/** Permanently disconnect a connected account, then re-list so the row disappears. */
async function deleteAccount(connectedAccountId: string): Promise<void> {
    const composio = getComposio();
    if (!composio) return;
    try {
        await composio.connectedAccounts.delete(connectedAccountId);
    } catch (e: any) {
        toErr("composio: delete connection failed:", String(e?.message ?? e));
    }
    void reconcileConnections();
}

/**
 * Authorize a NEW connected account for a toolkit, entirely out of band — the agent is
 * never involved, so this cannot reintroduce the deeplink-in-transcript hang/duplicate
 * bug. Emits `connection_link` for the host to open in the browser, then waits for the
 * connection to complete and re-reconciles.
 *
 * Prefer attaching the requested alias via an existing auth config (`authConfigs.list`
 * → `connectedAccounts.link`, the same proven call `reconnect` uses) so the new account
 * can become a default by alias. Fall back to `toolkits.authorize`, which discovers or
 * creates a Composio-managed auth config when none is listed yet.
 */
async function connectAccount(opts: { toolkit: string; alias?: string }): Promise<void> {
    const composio = getComposio();
    if (!composio) return;
    const slug = opts.toolkit.trim().toLowerCase();
    if (!slug) return;
    const alias = opts.alias?.trim() || undefined;
    try {
        let request: any;
        const configs: any = await (composio as any).authConfigs
            .list({ toolkit: slug })
            .catch(() => null);
        const authConfigId: string | undefined = configs?.items?.[0]?.id;
        if (authConfigId) {
            // `allowMultiple: true` is essential for an explicit "Connect an app" action:
            // without it `link()` throws ComposioMultipleConnectedAccountsError when an
            // ACTIVE account already exists for this auth config, so adding a *second*
            // account (e.g. a "work" alias alongside "personal") would silently fail.
            request = await composio.connectedAccounts.link(COMPOSIO_USER_ID, authConfigId, {
                alias,
                allowMultiple: true,
            });
        } else {
            // Fallback: no listed auth config yet. `toolkits.authorize` discovers/creates a
            // Composio-managed one. It takes no alias param (the SDK has no alias setter on
            // connectedAccounts), so this path connects without an alias — the common path
            // above (an existing auth config) is where the requested alias is honored.
            request = await (composio as any).toolkits.authorize(COMPOSIO_USER_ID, slug);
        }
        const url = request?.redirectUrl;
        if (typeof url !== "string" || !url) {
            toErr("composio: connect — no redirectUrl for", slug);
            return;
        }
        emit({ type: "connection_link", url, toolkit: slug });
        // Wait out of band for the user to finish; the 5-min poll covers an abandon.
        if (typeof request.waitForConnection === "function") {
            try {
                await request.waitForConnection();
            } catch {
                /* user may not complete it now — reconcile/poll will catch up later */
            }
        }
        void reconcileConnections();
    } catch (e: any) {
        toErr("composio: connect failed:", String(e?.message ?? e));
    }
}

// Watch connection health. The SDK trigger subscription is an *outbound* channel
// (works from localhost, no public webhook URL), but trigger fires don't carry
// expiry, so we use any event as a cheap nudge to re-reconcile and ALSO poll on an
// interval + at startup as the reliable detector.
async function startConnectionWatch(): Promise<void> {
    await reconcileConnections();
    const composio = getComposio();
    if (composio) {
        try {
            await composio.triggers.subscribe(() => {
                void reconcileConnections();
            });
        } catch (e: any) {
            toErr("composio: trigger subscribe failed (polling still active):", String(e?.message ?? e));
        }
    }
    setInterval(() => void reconcileConnections(), 5 * 60 * 1000);
}

/**
 * Default-account guidance appended to the system prompt, or "" when none is set.
 * Sourced from the extension config file (`readDefaultAccounts`) — the same store the
 * agent's resolver reads — so the prompt and the resolver can never disagree.
 */
function defaultAccountsPromptBlock(): string {
    const entries = Object.entries(readDefaultAccounts());
    if (entries.length === 0) return "";
    const lines = entries.map(([slug, selector]) => `  - ${slug}: account "${selector}"`).join("\n");
    return `\n\n## Default Composio accounts\nWhen a tool belongs to one of these toolkits, use the listed account:\n${lines}`;
}

async function main(): Promise<void> {
    // ── Conversation lifecycle ──────────────────────────────────────────────
    // One in-memory session holds the conversation across prompts. It is NOT
    // app-lifetime: IDLE_RESET_MS after the last response with no new prompt,
    // the session is disposed and a fresh one is created, so a prompt after a
    // long gap starts a clean thread.
    const IDLE_RESET_MS = 5 * 60 * 1000;

    let session: any = null;
    let sessionPromise: Promise<any> | null = null;
    let unsubscribe: (() => void) | null = null;
    let idleTimer: ReturnType<typeof setTimeout> | null = null;

    /** Create the session on first use (or after an idle reset); reuse it otherwise. */
    function ensureSession(): Promise<any> {
        if (!sessionPromise) {
            sessionPromise = (async () => {
                // Mirror createAgentSession's default loader wiring, but append the
                // notch's one-shot-command contract to the system prompt. The override
                // form keeps any user APPEND_SYSTEM.md instead of shadowing it.
                const cwd = process.cwd();
                const settingsManager = SettingsManager.create(cwd, agentDir);
                const resourceLoader = new DefaultResourceLoader({
                    cwd,
                    agentDir,
                    settingsManager,
                    appendSystemPromptOverride: (base: string[]) => [
                        ...base,
                        NOTCH_SYSTEM_PROMPT + defaultAccountsPromptBlock(),
                    ],
                });
                await resourceLoader.reload();

                const result = await createAgentSession({
                    // No persisted session file — conversations never outlive the process.
                    sessionManager: SessionManager.inMemory(),
                    // Model/provider/extensions all inherited from ~/.pi/agent settings.
                    settingsManager,
                    resourceLoader,
                });
                session = result.session;
                unsubscribe = session.subscribe(handleAgentEvent);
                return session;
            })().catch((e) => {
                // Don't cache the failure — let the next prompt retry.
                sessionPromise = null;
                throw e;
            });
        }
        return sessionPromise;
    }

    /** Drop the current conversation so the next ensureSession() starts fresh. */
    function teardownSession(): void {
        unsubscribe?.();
        unsubscribe = null;
        session?.dispose();
        session = null;
        sessionPromise = null;
    }

    /** (Re)start the idle countdown. Armed on each response, disarmed by each prompt. */
    function armIdleReset(): void {
        disarmIdleReset();
        idleTimer = setTimeout(() => {
            idleTimer = null;
            toErr(`idle reset: dropping conversation after ${IDLE_RESET_MS / 60000}min without a prompt`);
            teardownSession();
            // Recreate eagerly so the next prompt doesn't pay session-creation
            // latency. If this fails, ensureSession() retries on the next prompt.
            ensureSession().catch((e: any) =>
                toErr("idle reset: recreate failed (will retry on next prompt):", String(e?.message ?? e)),
            );
        }, IDLE_RESET_MS);
    }

    function disarmIdleReset(): void {
        if (idleTimer) {
            clearTimeout(idleTimer);
            idleTimer = null;
        }
    }

    // Tool calls the model is still streaming arguments for, keyed by contentIndex.
    const formingTools = new Map<number, FormingTool>();

    /**
     * Emit `tool_forming` for a (possibly still anonymous) tool call, but only when
     * something actually changed — toolcall_delta fires per token, so unconditional
     * re-emits would flood the wire.
     */
    function emitToolForming(index: number, toolName: string | null): void {
        const known = formingTools.get(index);
        const slug = toolName ? toolkitSlug(toolName) : null;
        if (known && known.tool === toolName && known.toolkit === slug) return;
        formingTools.set(index, { tool: toolName, toolkit: slug });
        emit({
            type: "tool_forming",
            index,
            tool: toolName,
            toolkit: slug,
            logo: slug ? `https://logos.composio.dev/api/${slug}` : null,
        });
    }

    /** Read a forming tool call's name out of the partial assistant message, if the provider exposes it. */
    function formingNameFromPartial(partial: any, contentIndex: number): string | null {
        const block = partial?.content?.[contentIndex];
        if (block?.type === "toolCall" && typeof block.name === "string" && block.name) {
            return block.name;
        }
        return null;
    }

    // Translate agent events → wire protocol. Named (not inline) so each fresh
    // session created by ensureSession() can re-subscribe the same handler.
    function handleAgentEvent(event: any): void {
        switch (event.type) {
            case "agent_start":
                formingTools.clear();
                emit({ type: "agent_start" });
                emitStatus("thinking");
                break;
            case "message_update": {
                const a = event.assistantMessageEvent;
                if (!a) break;
                if (a.type === "text_delta") {
                    emit({ type: "text_delta", delta: a.delta });
                } else if (a.type === "thinking_delta") {
                    emitStatus("thinking");
                } else if (a.type === "toolcall_start") {
                    // The name is provider-dependent here — emit immediately either way
                    // so the notch can show "Calling a tool…" instead of "Thinking…".
                    emitToolForming(a.contentIndex, formingNameFromPartial(a.partial, a.contentIndex));
                } else if (a.type === "toolcall_delta") {
                    // Upgrade to the real name once it becomes readable (emit-on-change only).
                    if (formingTools.get(a.contentIndex)?.tool == null) {
                        const name = formingNameFromPartial(a.partial, a.contentIndex);
                        if (name) emitToolForming(a.contentIndex, name);
                    }
                } else if (a.type === "toolcall_end") {
                    // Name is guaranteed now, and arguments are parsed — unwrap the
                    // composio meta-tool to the real toolkit (Gmail, Calendar, …).
                    const name =
                        unwrapComposioAction(a.toolCall.name, a.toolCall.arguments) ?? a.toolCall.name;
                    emitToolForming(a.contentIndex, name);
                } else if (a.type === "error") {
                    emit({ type: "error", message: "assistant error" });
                }
                break;
            }
            case "tool_execution_start": {
                // Unwrap composio_execute_tool → the real app (Gmail, Calendar, …) so
                // the notch shows that app's logo/color, not the generic Composio mark.
                const displayTool = unwrapComposioAction(event.toolName, event.args) ?? event.toolName;
                const slug = toolkitSlug(displayTool);
                // Reset status so a "thinking" after this tool re-emits.
                lastStatusWord = slug;
                emit({
                    type: "tool_start",
                    id: event.toolCallId,
                    tool: displayTool,
                    word: slug,
                    toolkit: slug,
                    logo: `https://logos.composio.dev/api/${slug}`,
                });
                break;
            }
            case "tool_execution_end":
                emit({ type: "tool_end", id: event.toolCallId, ok: !event.isError });
                break;
            case "agent_end":
                formingTools.clear();
                emitStatus("done");
                emit({ type: "done" });
                // Last response delivered — start the conversation-expiry countdown.
                armIdleReset();
                break;
        }
    }

    // Create the first session up front so launch/config failures surface immediately.
    try {
        await ensureSession();
    } catch (e: any) {
        emit({ type: "error", message: "init failed: " + String(e?.message ?? e) });
        emit({ type: "done" });
        process.exit(1);
    }

    // Begin watching connected-account health (reconcile + subscribe + poll). Best-effort
    // and non-blocking: failures only disable connection features, never the agent.
    void startConnectionWatch();

    async function handlePrompt(text: string): Promise<void> {
        disarmIdleReset(); // a prompt keeps the conversation alive
        lastStatusWord = null; // fresh run → let "thinking" emit again
        try {
            const s = await ensureSession();
            if (s.isStreaming) {
                await s.prompt(text, { streamingBehavior: "followUp" });
            } else {
                await s.prompt(text);
            }
        } catch (e: any) {
            emit({ type: "error", message: String(e?.message ?? e) });
            emit({ type: "done" });
            armIdleReset();
        }
    }

    async function handleAbort(): Promise<void> {
        try {
            await session?.abort();
        } catch {
            /* ignore */
        }
        emitStatus("aborted");
        emit({ type: "done" });
        armIdleReset();
    }

    function dispatch(msg: any): void {
        switch (msg?.type) {
            case "prompt":
                if (typeof msg.text === "string" && msg.text.trim()) void handlePrompt(msg.text);
                break;
            case "abort":
                void handleAbort();
                break;
            case "set_model":
                // v1 inherits the model from pi config; explicit selection is a follow-up.
                toErr("set_model requested but not implemented:", msg.id);
                break;
            case "list_connections":
                void reconcileConnections();
                break;
            case "reconnect":
                void reconnectAccount({
                    connectedAccountId: typeof msg.connectedAccountId === "string" ? msg.connectedAccountId : undefined,
                    toolkit: typeof msg.toolkit === "string" ? msg.toolkit : undefined,
                });
                break;
            case "connect":
                // Authorize a NEW account out of band (no agent involvement → no
                // deeplink-in-transcript bug). Replies with `connection_link`.
                if (typeof msg.toolkit === "string" && msg.toolkit.trim()) {
                    void connectAccount({
                        toolkit: msg.toolkit,
                        alias: typeof msg.alias === "string" ? msg.alias : undefined,
                    });
                }
                break;
            case "rename_connection":
                // { connectedAccountId, alias } — "" alias clears it. Re-lists after.
                if (typeof msg.connectedAccountId === "string" && msg.connectedAccountId.trim()) {
                    void renameAccount(msg.connectedAccountId, typeof msg.alias === "string" ? msg.alias : "");
                }
                break;
            case "delete_connection":
                // { connectedAccountId } — permanently disconnect, then re-list.
                if (typeof msg.connectedAccountId === "string" && msg.connectedAccountId.trim()) {
                    void deleteAccount(msg.connectedAccountId);
                }
                break;
            case "set_default":
                // { toolkit, selector } — "" selector clears the default → Automatic.
                // Writes the extension config file (the agent's source of truth), then
                // rebuilds the session so the next prompt carries the new defaults, and
                // re-emits connections so the UI ★ reflects the file.
                if (typeof msg.toolkit === "string") {
                    writeDefaultAccount(msg.toolkit, typeof msg.selector === "string" ? msg.selector : "");
                    teardownSession();
                    void reconcileConnections();
                }
                break;
            default:
                toErr("unknown message:", JSON.stringify(msg));
        }
    }

    // Read newline-delimited JSON commands from stdin.
    let buffer = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk: string) => {
        buffer += chunk;
        let nl: number;
        while ((nl = buffer.indexOf("\n")) >= 0) {
            const line = buffer.slice(0, nl).trim();
            buffer = buffer.slice(nl + 1);
            if (!line) continue;
            let msg: unknown;
            try {
                msg = JSON.parse(line);
            } catch {
                toErr("bad json line:", line);
                continue;
            }
            dispatch(msg);
        }
    });
    process.stdin.on("end", () => process.exit(0));

    emit({ type: "ready" });
}

void main();
