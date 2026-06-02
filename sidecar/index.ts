/**
 * pi-sidecar — a self-contained bridge between boring.notch (Swift) and the Pi
 * coding agent. Speaks newline-delimited JSON on stdin/stdout:
 *
 *   stdin   {"type":"prompt","text":"…"}   {"type":"abort"}   {"type":"set_model","id":"…"}
 *   stdout  {"type":"status","word":"thinking"}
 *           {"type":"tool_forming","index":0,"tool":"GMAIL_SEND_EMAIL","toolkit":"gmail",
 *            "logo":"https://logos.composio.dev/api/gmail"}   // tool/toolkit/logo null until known
 *           {"type":"tool_start","id":"t1","tool":"GMAIL_SEND_EMAIL","word":"gmail",
 *            "toolkit":"gmail","logo":"https://logos.composio.dev/api/gmail"}
 *           {"type":"tool_end","id":"t1","ok":true}
 *           {"type":"text_delta","delta":"Done — …"}
 *           {"type":"error","message":"…"}
 *           {"type":"done"}
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
} from "@mariozechner/pi-coding-agent";

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
                const agentDir = getAgentDir();
                const settingsManager = SettingsManager.create(cwd, agentDir);
                const resourceLoader = new DefaultResourceLoader({
                    cwd,
                    agentDir,
                    settingsManager,
                    appendSystemPromptOverride: (base: string[]) => [...base, NOTCH_SYSTEM_PROMPT],
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
