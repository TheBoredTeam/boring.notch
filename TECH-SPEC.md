# Kairo — Live Jarvis Technical Specification (as built)

Companion to `AGENT-ARCHITECTURE.md`. This doc maps the brief's spec onto
the actual code in this repo: where each module lives, the wire formats
between them, and the deltas vs the spec (some by choice, some still on
the to-do list).

Platform note: the brief described an iOS app. Kairo is **macOS** —
where iOS uses `UIAccessibility` + `ReplayKit`, macOS uses
`AXUIElement` (`ApplicationServices`) + `ScreenCaptureKit`. The
**iOS companion** target in `KairoiOS/` is scaffolded for the real
Dynamic Island when added in Xcode.

---

## 1. Module map (vs Spec §2–4)

| Spec module | Kairo location |
|---|---|
| Agent Core | `Kairo/Brain/` |
| Perception Engine | `Kairo/Perception/` + `Kairo/Executor/Tools/{ScreenTool,VisionTool,PerceiveTool}.swift` |
| Action Engine | `Kairo/Executor/` + `Kairo/Executor/Tools/` |
| LLM API client | `Kairo/Brain/LLMClient.swift` |
| State store | `Kairo/Memory/` (short / long / conversation) |
| UI surfacing | `Kairo/Voice/CaptionHUD.swift` + `Kairo/Orbie/` |

---

## 2. Agent Core (Spec §2)

### 2.1 LLM Integration

`Kairo/Brain/LLMClient.swift` defines:

```swift
protocol LLMClient: Sendable {
    var label: String { get }
    func chat(messages: [KairoChatMessage]) async throws -> String
}
```

Implementations:

- **`OllamaClient`** (existing) — local LLM at `localhost:11434`.
  `OllamaClient` is extended in `LLMClient.swift` to conform to
  `LLMClient` directly.
- **`AnthropicLLMClient`** — Claude 3.5 Sonnet via Messages API.
  Reads `ANTHROPIC_API_KEY` from env. Maps Kairo's flat
  `[KairoChatMessage]` (with `role: "system"`) to Anthropic's
  `system + messages` split.
- **`OpenAILLMClient`** — GPT-4o-class via Chat Completions.
  Reads `OPENAI_API_KEY`.
- **`LLMFallbackClient`** — wraps an ordered list; first success wins.

`KairoApp.swift` wires this as:

```swift
let llm: LLMClient = LLMFallbackClient([
    OllamaClient(),
    AnthropicLLMClient(),
    OpenAILLMClient()
])
```

Behavior: if Ollama is up, every request stays local. If Ollama
goes down, requests transparently route to Anthropic (when the
key is set), then to OpenAI. Privacy posture: local-first by
default, no leakage unless the user explicitly sets a cloud key.

### 2.2 Reasoning Loop (ReAct)

`Kairo/Brain/Brain.swift` — `KairoBrain.handle(input:ambient:)`.
Implements the spec's loop:

```
loop (bounded by maxToolHops = 6):
  THOUGHT + [CALL] | [ANSWER]    ← llm.chat
  if [ANSWER]: persist + return
  if [CALL]: run tool → append [OBSERVATION] → loop
  if neither: treat raw as ANSWER, return
```

State observers fire on every transition so the CaptionHUD can show
`◆ KAIRO · SEARCHING · "x"` / `READING · y` / `THINKING` /
`SPEAKING` to the user.

### 2.3 State Management (matches Spec §2.3)

| Spec layer | Kairo class | Persisted? | Where |
|---|---|---|---|
| Conversation History | `KairoConversationHistory` | **Yes** (JSON) | `~/Library/Containers/com.kairo.app/Data/Library/Application Support/Kairo/conversation_history.json` (sandbox) |
| Context Store | `KairoAmbientContext` + `KairoShortTermMemory` | No | RAM, rebuilt per turn |
| Goal Tracking | Implicit — the ReAct trace itself, surfaced via `lastTrace` and `KairoAgentState` | RAM | last turn only |

`KairoConversationHistory.Turn` records:

```swift
struct Turn: Codable, Hashable {
    let id: UUID
    let userInput: String
    let kairoReply: String
    let timestamp: Date
    let toolTrace: [String]   // THOUGHT / [CALL] / [OBSERVATION] log
}
```

`Brain.handle` calls `history?.record(...)` at the end of every turn
(both success and fallback paths) so the agent's memory survives
restart.

### 2.4 Tool Orchestration (Spec §2.4)

`Kairo/Executor/TieredExecutor.swift` is the **Tool Registry**. Each
tool conforms to:

```swift
protocol Tool {
    var name: String { get }
    var description: String { get }
    var permissionTier: PermissionTier { get }   // safe / destructive / critical
    var supportedTiers: [ExecutionTier] { get }  // native / browserExtension / uiAutomation
    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult
}
```

`PermissionGate` enforces tiers — `.destructive` requires user
confirmation, `.critical` requires a passphrase. The system-prompt
teaches the LLM the JSON schema:

```
[CALL] {"tool": "<name>", "args": {...}}
```

---

## 3. Perception Engine (Spec §3)

`Kairo/Perception/` contains the two new files:

- **`PerceptionContext.swift`** — the `PerceptionContext` /
  `UIElementDescription` schema from Spec §3.4.
- **`PerceptionEngine.swift`** — singleton walker over `AXUIElement`
  (macOS Accessibility) returning a compact `PerceptionContext`.

### 3.1 Input Sources

| Spec source | Kairo source |
|---|---|
| `AXUIElement` (UI tree) | **Yes** — `KairoPerceptionEngine` walks `kAXFocusedWindow` of the frontmost app's `AXUIElementCreateApplication(pid)`. Bounded by `maxDepth = 8`, `maxElements = 40`. |
| Screen Recording (ReplayKit on iOS) | macOS uses `ScreenCaptureKit` — see `ScreenTool` (OCR via Vision) and `VisionTool` (multimodal Claude). |
| OCR | `ScreenTool` uses `VNRecognizeTextRequest` already. |

### 3.2 Pre-processing

- **UI Tree Serialization**: the engine emits `[UIElementDescription]`
  (Codable), each with `id` (synthesized "0.2.4.1" path), `role`,
  `title`, `value`, `frame`, `isInteractable`, `children`. Container
  roles (`AXGroup`, `AXSplitGroup`, etc.) without text are filtered
  out so the LLM doesn't drown in plumbing.
- **Image Encoding**: `VisionClient` downscales to 60% and JPEG-encodes
  at 70% quality before base64'ing for Anthropic's `image` content type.
- **Context Filtering**: `perceive(query:)` takes an optional substring
  that filters the element list to ones matching by title / value /
  role.

### 3.3 Multimodal LLM (matches Spec §3.3)

`Kairo/Brain/VisionClient.swift` + `Executor/Tools/VisionTool.swift`
— captures the screen and asks Claude 3.5 Sonnet a question via the
Messages API. Configured by `ANTHROPIC_API_KEY`. The LLM is taught
in the system prompt:

```
vision   — args: {"question": "<what to ask about the screen>"}
           Use when John references "this" or wants screen help.
```

### 3.4 Output Schema (matches Spec §3.4 exactly)

```swift
struct PerceptionContext: Codable {
    let activeAppName: String
    let activeAppBundleID: String?
    let activeWindowTitle: String?
    let screenSummary: String
    let relevantUIElements: [UIElementDescription]
    let screenshotPath: String?
    let timestamp: Date
}

struct UIElementDescription: Codable {
    let id: String              // "0.2.4.1"
    let role: String            // "AXButton", "AXTextField", …
    let title: String?
    let value: String?
    let frame: CGRect
    let isInteractable: Bool
    let children: Int
    var summary: String         // one-line for LLM injection
}
```

The `perceive` tool serializes the elements as pretty JSON and prefixes
with the summary line so the LLM gets structured data without parsing
the full tree itself.

---

## 4. Action Engine (Spec §4)

`Kairo/Executor/TieredExecutor.swift` is the registry. Tool list at
the time of writing:

| Tool | Category | Permission |
|---|---|---|
| `weather` | ExternalAPITool (OpenWeatherMap) | `.safe` |
| `apple_music` | SystemTool (AppleScript) | `.safe` |
| `youtube` | SystemTool / browser-ext | `.safe` |
| `clipboard` | SystemTool | `.safe` |
| `see_screen` | Perception / OCR | `.safe` |
| `vision` | Perception / multimodal | `.safe` |
| `perceive` | **NEW — Perception / accessibility** | `.safe` |
| `system` | SystemTool (shell/open_app) | `.destructive` |
| `web_search` | WebTool (Brave / DDG) | `.safe` |
| `web_read` | WebTool (HTML fetch + strip) | `.safe` |
| `smart_home` | ExternalAPITool (Home Assistant) | `.safe` |
| `calendar_event` | SystemTool (EventKit write) | `.destructive` |

### 4.2 Tool Execution — examples

**Web Search & Scraper** (Spec §4.2):
- `SearchTool` → Brave Search API (env `BRAVE_SEARCH_API_KEY`)
  → falls back to DuckDuckGo Instant Answer (no key).
- `WebReadTool` → URLSession fetch → regex HTML stripper (drops
  script/style/head/svg, block→newline, tag→empty, entity decode
  incl. numeric `&#1234;` / `&#xABCD;`). No SwiftSoup dependency to
  keep the binary lean; SwiftSoup can swap in cleanly later.

**External APIs** (Spec §4.2):
- `WeatherTool` → existing `WeatherService` (OpenWeatherMap).
- `SmartHomeTool` → Home Assistant REST shim. Env-driven entity
  resolution: `KAIRO_HASS_LIGHTS=light.living_room,light.kitchen`.

**System Actions** (Spec §4.2):
- `CalendarEventTool` → EventKit `requestFullAccessToEvents` on
  macOS 14+, then `EKEventStore.save(event:span:)`.
- `SystemTool` → AppleScript (`tell application X to activate`) +
  `Process` (zsh shell).

### 4.3 Error Handling (matches Spec §4.3)

Every tool returns `ToolResult(success: Bool, output: String, tierUsed: ExecutionTier)`.
Failures are returned, not thrown — the ReAct loop reads them as
`[OBSERVATION] error: ...` and the LLM re-plans.

### 4.4 Output Schema (matches Spec §4.4 in spirit)

```swift
struct ToolResult {
    let success: Bool
    let output: String        // plain text or JSON-encoded
    let tierUsed: ExecutionTier
}
```

Slight difference vs Spec: we don't carry `toolName` in the result
(the executor's call site already knows it) and we use `output` for
both success and error cases — the `success` boolean disambiguates.
Both are fine for our ReAct loop's purposes.

---

## 5. Integration points & data flow (Spec §5)

```
                ┌────────────────┐
                │ User input or  │
                │  wake word     │
                └───────┬────────┘
                        │
                        ▼
        ┌─────────────────────────────┐
        │  ConversationLoop / Menu    │
        │  (Voice/ConversationLoop)   │
        └───────┬─────────────────────┘
                │
                ▼
        ┌───────────────────┐      ┌──────────────────────┐
        │  KairoBrain       │◀────▶│  ContextBuilder      │
        │  (ReAct loop)     │      │  (LTM + STM + Hist + │
        │                   │      │   AmbientContext)    │
        └─┬────────────┬────┘      └──────────────────────┘
          │            │
          │ chat()     │ run tool
          ▼            ▼
    ┌──────────┐  ┌──────────────┐
    │ LLM      │  │ TieredExecutor│
    │ Fallback │  │   │
    │ chain    │  │   ├─► WebReadTool ──→ URLSession ──→ host
    └──────────┘  │   ├─► SearchTool ──→ Brave / DDG
                  │   ├─► PerceiveTool ──→ PerceptionEngine ──→ AXUIElement
                  │   ├─► VisionTool ──→ VisionClient ──→ Claude
                  │   ├─► CalendarEventTool ──→ EventKit
                  │   ├─► SmartHomeTool ──→ HASS REST
                  │   └─► (etc)
                  └──────────────┘
                        │
                        ▼
                ┌──────────────────┐
                │  ToolResult      │
                │  → [OBSERVATION] │
                └──────────────────┘
                        │
                        └────────► Brain loops or finalizes
                                            │
                                            ▼
                            ┌─────────────────────────────────┐
                            │  KairoCaptionHUD + Orbie panel  │
                            │  + KairoTTSEngine               │
                            └─────────────────────────────────┘
                                            │
                                            ▼
                            ┌─────────────────────────────────┐
                            │  KairoConversationHistory       │
                            │  persists the turn              │
                            └─────────────────────────────────┘
```

---

## 6. Security & Privacy (Spec §6)

| Spec concern | Status |
|---|---|
| User consent for screen / mic | ✅ — `WakeWord` is opt-in via menubar; `vision` and `see_screen` use macOS Screen Recording consent gate; `perceive` requires Accessibility permission |
| Data minimization | ✅ — `web_read` caps at 6KB, `perceive` caps elements at 40, vision JPEG at 60% scale |
| Secure storage of keys | 🟡 — currently env-file based (`~/.kairo.env`); Keychain wrapper is on the to-do list |
| On-device processing | ✅ default — Ollama is the first fallback link; cloud only when user explicitly sets keys |
| Rate limiting | ❌ — not yet implemented; tools have request timeouts but no per-window cap |

---

## 7. What's done vs the spec

**Done (matches spec):**

- §2.1 LLM client module ✅ (`LLMClient.swift`)
- §2.2 ReAct loop ✅ (`Brain.swift` with bounded hops + state observer)
- §2.3 State management ✅ (3-layer: ambient + short-term RAM + persistent history)
- §2.4 Tool orchestration ✅ (`TieredExecutor`)
- §3.1 Accessibility input ✅ (`PerceptionEngine.swift`)
- §3.1 OCR ✅ (`ScreenTool`)
- §3.2 UI tree serialization ✅ (`UIElementDescription`)
- §3.3 Multimodal LLM ✅ (`VisionTool` + `VisionClient` → Claude)
- §3.4 Output schema ✅ (matches `PerceptionContext` layout)
- §4.1 Tool registry ✅
- §4.2 Web search + scraper ✅
- §4.2 External APIs ✅ (Weather, HASS)
- §4.2 System actions ✅ (Calendar, AppleScript, shell)
- §4.3 Error handling ✅ (success bool on every tool)
- §4.4 Output schema ✅ (minor variation — no separate `toolName` field)
- §5 Integration & data flow ✅ (diagram above)

**Partial:**

- §4.2 AppIntents / SiriKit — not wired. macOS supports both;
  next session candidate.
- §6 Secure storage — env-file only, no Keychain yet.

**Open:**

- §7 Integration tests — none written yet. Each module is at the
  right shape for `XCTestCase` to call `KairoBrain.handle(...)` /
  `KairoPerceptionEngine.perceive(...)` directly. Adding a `KairoTests`
  target is a separate session.
- §6 Rate limiting — not implemented.
- §4.2 OpenTable, Uber, Stripe-style tools — pattern shown by
  `CalendarEventTool`. Each needs ~80 LOC.

---

## 8. File map (post-this-commit)

```
Kairo/Brain/                     ← Agent Core
  Brain.swift                      ReAct loop, tool dispatch, state observer
  ContextBuilder.swift             LLM message assembly
  LLMClient.swift                  protocol + Anthropic / OpenAI / Fallback
  OllamaClient.swift               local LLM (now conforms to LLMClient)
  SystemPrompt.swift               identity + ReAct protocol + tool listing
  VisionClient.swift               Claude multimodal screen-capture client

Kairo/Memory/                    ← State
  AmbientContext.swift             time, location, focused app per turn
  ShortTermMemory.swift            20-entry ring buffer, RAM
  LongTermMemory.swift             persisted facts about user
  ConversationHistory.swift        persisted turns (NEW)

Kairo/Perception/                ← Perception Engine (NEW)
  PerceptionContext.swift          struct matching Spec §3.4
  PerceptionEngine.swift           AXUIElement walker

Kairo/Executor/                  ← Action Engine
  TieredExecutor.swift             tool registry
  PermissionGate.swift             safe / destructive / critical
  ExecutionTier.swift              native / browserExtension / uiAutomation
  Tools/
    WeatherTool.swift              ExternalAPI
    AppleMusicTool.swift           System
    YouTubeTool.swift              System / Browser
    ClipboardTool.swift            System
    ScreenTool.swift               Perception / OCR
    SystemTool.swift               System (open_app / shell)
    SearchTool.swift               Web
    SmartHomeTool.swift            ExternalAPI (HASS)
    WebReadTool.swift              Web
    CalendarEventTool.swift        System (EventKit)
    VisionTool.swift               Perception / multimodal
    PerceiveTool.swift             Perception / AX (NEW)

Kairo/Voice/                     ← UI / I/O
  TTSEngine.swift                  AVSpeechSynthesizer
  SpeechRecognizer.swift           SFSpeechRecognizer wrapper
  WakeWord.swift                   opt-in "hey kairo"
  ConversationLoop.swift           one-turn voice flow
  CaptionHUD.swift                 caption window + agent-state header

Kairo/Coordinator/
  OrbCoordinator.swift             Hologram ↔ Orbie handoff
  KairoRuntime.swift               shared singleton

Kairo/Orbie/                     ← Visible surfaces
  OrbieShell.swift
  Views/                           textResponse, searchResults, etc.

KairoiOS/                        ← iOS companion scaffold
  KairoiOSApp.swift
  LiveActivity/
    KairoActivityAttributes.swift
    KairoActivityWidget.swift
  Views/CompanionRootView.swift
  README.md

AGENT-ARCHITECTURE.md            ← agent-layer rationale
TECH-SPEC.md                     ← (you are here) tech-spec ↔ code map
DESIGN-RATIONALE.md              ← visual design choices
```
