/**
 * pi-sidecar — a self-contained bridge between boring.notch (Swift) and the Pi
 * coding agent. Speaks newline-delimited JSON on stdin/stdout:
 *
 *   stdin   {"type":"prompt","text":"…"}   {"type":"abort"}   {"type":"set_model","id":"…"}
 *   stdout  {"type":"status","word":"thinking"}
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
 */

import { createAgentSession, SessionManager } from "@mariozechner/pi-coding-agent";

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

async function main(): Promise<void> {
    let session;
    try {
        const result = await createAgentSession({
            // No persisted session file — each app run is ephemeral.
            sessionManager: SessionManager.inMemory(),
            // Model/provider/extensions all inherited from ~/.pi/agent settings.
        });
        session = result.session;
    } catch (e: any) {
        emit({ type: "error", message: "init failed: " + String(e?.message ?? e) });
        emit({ type: "done" });
        process.exit(1);
    }

    // Translate agent events → wire protocol.
    session.subscribe((event: any) => {
        switch (event.type) {
            case "agent_start":
                emitStatus("thinking");
                break;
            case "message_update": {
                const a = event.assistantMessageEvent;
                if (!a) break;
                if (a.type === "text_delta") {
                    emit({ type: "text_delta", delta: a.delta });
                } else if (a.type === "thinking_delta") {
                    emitStatus("thinking");
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
                emitStatus("done");
                emit({ type: "done" });
                break;
        }
    });

    async function handlePrompt(text: string): Promise<void> {
        lastStatusWord = null; // fresh run → let "thinking" emit again
        try {
            if (session.isStreaming) {
                await session.prompt(text, { streamingBehavior: "followUp" });
            } else {
                await session.prompt(text);
            }
        } catch (e: any) {
            emit({ type: "error", message: String(e?.message ?? e) });
            emit({ type: "done" });
        }
    }

    async function handleAbort(): Promise<void> {
        try {
            await session.abort();
        } catch {
            /* ignore */
        }
        emitStatus("aborted");
        emit({ type: "done" });
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
