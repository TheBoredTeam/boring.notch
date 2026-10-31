# Calendar Live Activity — Design

## Goal

A live activity in the **closed** notch that counts down to the user's next
calendar event, then to the current event ending. It appears only near an
event and coexists with the existing music live activity: the **left** slot
shows the music icon (album art) when music plays, otherwise a calendar icon;
the **right** slot shows a **calendar ring** that drains as time runs out.

## Behavior

- **When it shows:** an event is within the lead window (default **30 min**)
  before its start, or is currently in progress. Hidden otherwise.
- **All-day events are ignored** — no meaningful countdown.
- **Two phases**, driven by `EventModel.eventStatus`:
  - `.upcoming` and within lead window → label `"<title> in 12m"`; ring drains
    over the lead window (full at 30m out, empty at start).
  - `.inProgress` → label `"<title> ends in 8m"`; ring drains over the event's
    duration (full at start, empty at end).
  - `.ended` → dropped; the next qualifying event is selected.
- **Granularity:** minute-level. A 1-minute tick recomputes label + progress.
  No per-second timer. (`ponytail:` upgrade to per-second only if a smooth
  ring is later wanted.)
- **Coexistence with music:** no either/or. Music keeps the left slot; the
  calendar ring is added on the right. With no music, the left icon becomes a
  calendar SF Symbol so the activity still reads as calendar-related.

## Components

1. **`CalendarManager` addition** — a method returning **today's** events for
   the selected calendars (00:00 → 24:00), because the existing
   `CalendarManager.events` only holds the calendar-UI's week window.
   `calendarService` is private, so this lives on `CalendarManager` (which owns
   the service and the selected-calendar set) rather than being reached into.

2. **`CalendarLiveActivityViewModel`** (new, `managers/`) — `@MainActor`
   `ObservableObject`:
   - On a 1-minute tick and on `.EKEventStoreChanged`, reloads today's events.
   - Picks the earliest event that is in-window (`.upcoming` within lead) or
     `.inProgress`, ignoring all-day events.
   - Publishes `activeEvent: EventModel?`, `progress: Double` (0…1), and
     `label: String`, recomputed each tick.
   - Stops ticking when the setting is off.

3. **`CalendarLiveActivity` view** (new, `components/Live activities/`) — the
   right-side ring: a trimmed `Circle` (`trim(from:to:)` = `progress`) with a
   calendar SF Symbol centered, sized like the music spectrum slot using
   `vm.effectiveClosedNotchHeight`.

4. **`ContentView` wiring** — in the closed-notch branch, when
   `calendarVM.activeEvent != nil` and the setting is on, render the ring on
   the right; when music is not playing, swap the left icon to a calendar
   symbol. Reuses the existing `MusicLiveActivity` left/spacer/right structure.

5. **Setting** — `@AppStorage("calendarLiveActivityEnabled") var … = true` on
   `BoringViewCoordinator` (mirrors `musicLiveActivityEnabled`), plus a
   `Toggle("Show calendar live activity", …)` in the Settings "Media playback
   live activity" section.

## Data flow

```
.EKEventStoreChanged / 1-min tick
  → VM reloads today's events (via CalendarManager)
  → picks earliest in-window or in-progress event (skip all-day)
  → publishes label + progress (0…1)
  → ContentView renders ring (right) + calendar icon (left if no music)
```

## Edge cases

- No calendar permission / no events → `activeEvent = nil`, nothing shows.
- Overlapping / multiple qualifying events → pick the earliest `start`.
- Setting off → VM stops ticking, slot empty.
- Event ends between ticks → resolved on the next tick (≤ 1 min stale).

## Testing

One self-check on the **pure** selection + progress logic: given a fixed
`now` and a list of events, assert which event is picked, the phase
(upcoming vs in-progress), and the `progress` fraction. No EventKit needed —
the selection/progress function takes `now` and `[EventModel]` as inputs.

## Deliberate simplifications (ponytail)

- 1-minute tick, not per-second — minute-granularity countdown is enough.
- Lead window fixed at 30 min (no per-user setting) — add a stepper only if
  requested.
- Reuses existing sizing constants and the `MusicLiveActivity` layout rather
  than a new layout system.
