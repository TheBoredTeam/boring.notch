# Kairo — Live Jarvis Agent Architecture

Companion to `DESIGN-RATIONALE.md`. This doc covers the **agent layer**:
how Kairo thinks, what tools it has, how it perceives the screen, and
how state flows from "user said something" through "tools ran, result
synthesized, UI updated."

The target is a fully autonomous research + action agent on **macOS**
(not iOS — the brief described an iOS app but Kairo lives in the
MacBook camera notch). The iOS companion target in `KairoiOS/` mirrors
this with a real Dynamic Island when it's added in Xcode.

---

## 1. Agent loop — ReAct, Swift edition

Kairo uses a **ReAct (Reason + Act) loop** [Yao et al. 2022]. Each turn:

```
Loop:
  ┌─────────────┐   the model emits a free-text THOUGHT, then either
  │   THOUGHT   │   a tool call (Action) or a final answer
  └──────┬──────┘
         │
   ┌─────┴──────┐
   │            │
   ▼            ▼
[CALL]      [ANSWER]  ← final, exits loop
   │
   ▼
┌─────────────┐   tool returns synchronously; result is appended as
│ OBSERVATION │   an [OBSERVATION] system message
└──────┬──────┘
       │
       └──► (loop back to Thought)
```

Implemented in `Kairo/Brain/Brain.swift` as `KairoBrain.handle(input:ambient:)`.
The model is taught the protocol via `Kairo/Brain/SystemPrompt.swift`:

```
THOUGHT: I should check the weather first.
[CALL] {"tool": "weather", "args": {}}
```

System replies with:

```
[OBSERVATION] ok: Overcast, 25°C in Kampala. Rain later this afternoon.
```

Model continues:

```
THOUGHT: User asked if it's a good day for a run.
[ANSWER] Risky — overcast and rain later. Either head out now or hold
until tomorrow morning.
```

The loop is bounded by `maxToolHops = 6` (was 4; raised for research
flows). Each hop emits a state change (see §5).

---

## 2. State management

Three layers, each in `Kairo/Memory/`:

| Layer | Class | Persisted? | Lifetime |
|---|---|---|---|
| **Ambient** | `KairoAmbientContext` | No | One turn — time, location, focused app |
| **Short-term** | `KairoShortTermMemory` | No (RAM) | Process lifetime — last 20 turns |
| **Long-term** | `KairoLongTermMemory` | Yes (JSON, sandbox Application Support) | Forever — facts about the user |

The `ContextBuilder` (`Kairo/Brain/ContextBuilder.swift`) assembles
the LLM messages from all three plus the system prompt. Per turn it
emits 3 system messages (prompt + facts + ambient) + 5 most recent
short-term entries + the new user input.

Inside a ReAct loop, the running message list grows with each hop —
the assistant's [CALL] / [ANSWER] becomes an assistant message, the
[OBSERVATION] becomes a user message. Short-term memory only records
the *final* user input + final answer (not intermediate hops).

---

## 3. Tool inventory

Tools live in `Kairo/Executor/Tools/`. Each conforms to:

```swift
protocol Tool {
    var name: String { get }
    var description: String { get }
    var permissionTier: PermissionTier { get }   // safe / destructive / critical
    var supportedTiers: [ExecutionTier] { get }  // native / browserExtension / uiAutomation
    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult
}
```

| Tool | Status | What it does |
|---|---|---|
| `weather` | ✅ real | OpenWeatherMap via `WeatherService`, returns current + 7-day |
| `apple_music` | ✅ real | AppleScript: play/pause/next/prev/play-query |
| `youtube` | ✅ real | WebSocket → Chrome extension (browser tier), AppleScript fallback |
| `clipboard` | ✅ real | NSPasteboard string read |
| `see_screen` | ✅ real | `ScreenCaptureKit` capture + Vision OCR |
| `system` | ✅ real | `open_app` (AppleScript) / `shell` (Process /bin/zsh) |
| `web_search` | ✅ real | Brave Search API (when `BRAVE_SEARCH_API_KEY` set), DuckDuckGo Instant Answer fallback |
| `web_read` | ✅ real | **NEW** — fetches URL, strips HTML, returns first ~6KB of plain text |
| `smart_home` | ✅ real | Home Assistant REST shim (`HASS_URL` + `HASS_TOKEN`) |
| `calendar_event` | ✅ real | **NEW** — EventKit create event (today / tomorrow / explicit date) |
| `vision` | 🟡 partial | **NEW** — captures screen + asks a multimodal LLM (Claude API, optional) |

The agent calls them via `TieredExecutor.run(toolName:args:)`. Each
call goes through `PermissionGate` first — `safe` passes silently,
`destructive` shows a confirm dialog, `critical` requires a passphrase.

---

## 4. Screen perception

Two surfaces, each opt-in:

### A. On-demand capture — `see_screen`
- Triggered when the agent calls the `see_screen` tool
- `ScreenCaptureKit` captures the active display
- `VNRecognizeTextRequest` (Vision framework) extracts text
- Returns the text content + dimensions
- Used for: *"What does it say on my screen right now?"*, *"Read that PDF"*

### B. Multimodal vision — `vision`
- When `ANTHROPIC_API_KEY` is set in `~/.kairo.env`, the agent can call
  the `vision` tool with a question
- Captures the screen, base64-encodes the image, asks Claude 3.5 Sonnet
  via the Messages API with the image attached
- Returns Claude's interpretation
- Used for: *"What's on this Stripe dashboard?"*, *"Read this receipt"*,
  *"Is that error from the build or my code?"*

Without an API key, the tool returns a clear error message that the
ReAct loop can route around.

### C. Future — proactive perception (not yet wired)
A background loop that captures + OCRs the screen every N seconds,
diffs against the last sample, and triggers the agent on meaningful
changes (e.g., a flight confirmation email opens → agent offers to
add to calendar). Foundation is there — just needs a `KairoScreenWatcher`
class that runs the on-demand path on a timer and gates via diffing.

---

## 5. Agent state — visible to the user

The ReAct loop emits state changes via a `KairoAgentState` enum:

```swift
enum KairoAgentState {
    case idle
    case listening
    case thinking            // model is generating a thought
    case searching(String)   // calling web_search with this query
    case reading(URL)        // calling web_read on this URL
    case seeing              // capturing + analyzing screen
    case acting(String)      // calling any destructive tool by name
    case speaking            // final answer is being delivered
}
```

The CaptionHUD's header pill shows a mono-caps tag for each state:

```
◆ KAIRO · SEARCHING · "italian restaurants kampala"
◆ KAIRO · READING · serena-hotel.ug/restaurant
◆ KAIRO · THINKING
◆ KAIRO · SPEAKING · weather
```

`KairoBrain.stateObserver: ((KairoAgentState) -> Void)?` is set by
the AppDelegate to `KairoCaptionHUD.shared.updateState(_:)`. Every
tool call begins with a state push; the loop returns to `.thinking`
between hops; the final answer transitions to `.speaking`.

---

## 6. Privacy & security

- **Local-first LLM**: Default backend is Ollama on `localhost:11434`.
  No prompts leave the machine unless the user has explicitly set
  `ANTHROPIC_API_KEY` or `BRAVE_SEARCH_API_KEY` in their env file.
- **Screen capture consent**: macOS prompts for Screen Recording the
  first time `ScreenCaptureKit` is invoked. `see_screen` and `vision`
  both go through this gate.
- **Microphone + speech consent**: Required for `KairoWakeWord` and
  `KairoConversationLoop`. Wake word is **opt-in** (menubar toggle)
  so app launch never touches the mic without explicit user action.
- **Tool permission tiers**:
  - `.safe` — read-only or user-explicit (weather, clipboard, web_search,
    web_read, see_screen, vision)
  - `.destructive` — modifies state (smart_home, calendar_event, system shell)
  - `.critical` — would need a hardcoded passphrase before execution
    (none currently use this; reserved for "transfer money" / "delete X"
    style ops)
- **Secrets**: API keys live in `~/.kairo.env` or `~/AI/Kairo/.env`,
  loaded once at boot via `AppDelegate.loadEnvFile`, never written
  back, never sent to the LLM in the system prompt.

---

## 7. UI states — Dynamic Island analogue

The notch + Orbie + CaptionHUD ladder mirrors what an iOS Live Activity
would do:

| Distance | Surface | Purpose |
|---|---|---|
| Always visible | **Hologram orb** (or the closed notch on MacBooks without one) | Idle presence — "Kairo is here" |
| On wake / F5 | **Orbie** floats out from the hologram | Listening / thinking / single-line response |
| Final answer | **CaptionHUD** appears below the notch | Long-form text the user can read |
| Long content | **Orbie panel** (textResponse / searchResults views) | Multi-result, multi-paragraph |
| Live-activity | **iOS companion target** (when added) | Real Dynamic Island on iPhone, mirrored from Mac |

Phase 5 in the redesign already built the iOS Dynamic Island in
`KairoiOS/LiveActivity/`. Pair-and-mirror is future work.

---

## 8. Where this falls short of real Iron-Man Jarvis

Honest assessment so we know what's still on the table:

1. **No streaming TTS.** Ollama supports streaming but the brain waits
   for the full answer before speaking. Reply feels delayed for long
   answers. Next ~150 LOC.
2. **No cloud fallback.** If Ollama is down, the brain dies. Need
   a "Claude / OpenAI when Ollama is unreachable" adapter.
3. **No streaming agent trace.** Tool hops happen serially; the
   CaptionHUD shows state per hop but the model can't currently
   speak mid-loop ("I'm checking 3 sites — give me a sec").
4. **No proactive triggers.** No background screen-watch, no calendar
   reminder pings, no "your battery is at 10%, plug in".
5. **No transactional tools.** OpenTable / Uber / Stripe etc. aren't
   wired. Pattern is right — `calendar_event` is the template — just
   need per-service tools.
6. **No memory consolidation.** Short-term resets each launch; no
   vector store for semantic recall.

The architecture is shaped for all of these. They're additions, not
restructurings.

---

## File map

```
Kairo/Brain/                    ← agent loop
  Brain.swift                     ReAct loop, tool dispatch
  ContextBuilder.swift            assembles LLM messages
  OllamaClient.swift              local LLM
  SystemPrompt.swift              identity + tool protocol
  VisionClient.swift              ← NEW Claude vision wrapper

Kairo/Executor/                 ← tools
  TieredExecutor.swift            registry + dispatch
  PermissionGate.swift            safe / destructive / critical
  Tools/
    WeatherTool.swift
    AppleMusicTool.swift
    YouTubeTool.swift
    ClipboardTool.swift
    ScreenTool.swift
    SystemTool.swift
    SearchTool.swift
    SmartHomeTool.swift
    WebReadTool.swift             ← NEW
    CalendarEventTool.swift       ← NEW
    VisionTool.swift              ← NEW

Kairo/Memory/                   ← state
  ShortTermMemory.swift           20-entry ring buffer
  LongTermMemory.swift            JSON-persisted facts
  AmbientContext.swift            time, location, focused app

Kairo/Voice/                    ← input / output
  SpeechRecognizer.swift
  TTSEngine.swift                 AVSpeechSynthesizer
  WakeWord.swift                  opt-in continuous SFSpeechRecognizer
  ConversationLoop.swift          one-turn voice flow
  CaptionHUD.swift                always-visible caption window

Kairo/Coordinator/
  OrbCoordinator.swift            hologram ↔ orbie handoff
  KairoRuntime.swift              shared singleton

Kairo/Orbie/                    ← visible surfaces
  OrbieShell.swift
  Views/                          textResponse, searchResults, etc.

AGENT-ARCHITECTURE.md           ← you are here
DESIGN-RATIONALE.md             ← visual design choices
```
