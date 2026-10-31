# Collapsed notch activities

Boring Notch owns presentation. An activity supplies a leading view, a trailing view, and a lifecycle descriptor. It never inserts a camera spacer, sizes the window, or decides which other feature to replace.

## Layers and ownership

- `LiveActivityService` is a main-actor lifecycle registry and deterministic selector. It depends on Foundation/Combine, an injectable selection policy, and an injectable deadline scheduler. It knows no feature names or view types.
- `LiveActivityCenter` binds registered identities to type-erased `NotchLiveActivity` renderers. Erasure happens at this heterogeneous collection boundary; individual providers retain normal SwiftUI view types.
- `NotchActivityHost` measures both regions, gives them equal bounded space around the centered camera exclusion area, clips each independently, and animates width changes. Reduced Motion disables its inherited and local animations. Its measured width also sizes the parent's chin/hover area.
- `BuiltinLiveActivitySource` adapts existing managers into registrations. Music, notification, battery, inline OSD, and the idle face use the same host. `ExtensionManager` is another adapter; it is not part of the scheduler.

The center and built-in source live for the application session. Recreating a window for a display or lock transition does not end activities. Selection is keyed by display UUID and surface. A desktop context can suppress ordinary content in fullscreen while still allowing system interrupts.

Descriptors and contexts default to `.desktop`. An activity must explicitly choose `.lockScreen` to render in `LockedLiveActivityView`, which has no route to desktop providers, expanded UI, or gesture handlers. `NotchWindowManager` closes ordinary windows before showing a separate noninteractive secure window, using the same two-side geometry. Only a locked, awake, active session can show that window. Publisher withdrawal removes it; the existing lock-screen setting can retain an empty shape. Display and preference changes reconcile secure windows without creating a second provider instance for unchanged geometry.

## Implementing an in-process provider

```swift
@MainActor
struct DownloadActivity: NotchLiveActivity {
    let progress: Double
    var descriptor: LiveActivityDescriptor {
        LiveActivityDescriptor(
            id: LiveActivityID(namespace: "com.example.downloads", name: "download-42"),
            priority: 25
        )
    }
    func leading(context: LiveActivityViewContext) -> some View {
        Image(systemName: "arrow.down.circle")
    }
    func trailing(context: LiveActivityViewContext) -> some View {
        Text(progress, format: .percent.precision(.fractionLength(0)))
    }
}

// A controller or service owns this token, not a transient View.body evaluation.
let registration = try center.register(DownloadActivity(progress: 0))
try registration.update(DownloadActivity(progress: 0.5))
registration.end()         // hide, retaining ownership of this ID
try registration.update(DownloadActivity(progress: 0.75)) // new activation
registration.unregister() // terminal; releases the ID and renderer
```

An observable provider may update its own view model without updating its descriptor. Repeated payload updates must keep the activity ID stable; changing an ID means a new activity. Sources explicitly unregister during teardown. Dropping a token also schedules cleanup on the main actor. Duplicate registrations fail instead of silently replacing another owner. Old tokens and canceled deadline callbacks cannot mutate a replacement registration.

An ID has separate namespace and name fields. A transport adapter assigns the namespace from the verified source, validates its wire data, and owns its registration tokens. Do not expose a raw `register(anyNamespace:)` command to external callers.

## Selection contract

The default policy orders by presentation class, priority, then activation order, with a deterministic identity tie-breaker. It has three presentation classes:

| Class | Meaning | User browsing |
| --- | --- | --- |
| interrupt | Temporary system ownership, such as inline OSD or power status | Cannot be swiped away |
| activity | Ongoing or transient activity, such as music, notifications, or downloads | Cycles by stable identity |
| background | Idle fallback | Considered when no ordinary activity is eligible |

The user can select an existing lower-priority activity. A **new activation** at the same or higher priority interrupts that choice. Refreshing the same active ID does not. When the interrupting activity ends, the earlier user choice resumes if it is still eligible. System interrupts leave that choice intact. Selection on one display does not change selection on another.

Lifetimes are persistent or absolute deadlines. A single cancelable deadline per registration replaces polling. Renewing a deadline invalidates the old callback; snapshots also filter expired content even if the event loop has not delivered the callback yet. The notification manager remains the owner of notification timing and hover holds; the adapter does not start a competing timer.

`LiveActivitySelectionPolicy` can replace ordering and selection without changing providers or layout. `LiveActivityScheduling` makes clock and expiry behavior testable. Keep app policy here rather than adding feature switches to ContentView.

## Geometry and interaction

The host reserves the current display's camera width plus edge clearance. Each side receives the larger of the two intrinsic widths, capped to half of the remaining window width. This intentionally balances asymmetric and one-sided content so the camera remains centered. The total remains within the existing 640-point window budget (including outer padding). Providers should truncate or adapt within their bounded region and never rely on drawing outside it.

Only side contents transition; the protected center never slides across the camera. Width measurement renders one copy of provider content, avoiding duplicate timers or AppKit controllers. Extensions return a fresh controller for each region/display. Horizontal browsing is owned by the activity stack; media track gestures apply only when music owns the slot and the stack is not browsable.

Hello/onboarding, the full-width Now Playing fallback notice, the expanded notch workspace, and legacy lower OSD/music peeks remain system presentations. They are not forced into a two-region collapsed activity. An extension does not replace these surfaces through this API.

## Independent extensions

The Swift protocol is an internal host contract, not a binary SDK. Independently compiled bundles use the versioned C/AppKit boundary in [extension-api.h](extension-api.h). The adapter turns their publications into the same registrations and supplies the same generic layout. See [extensions.md](extensions.md) and the standalone example for packaging, lifecycle, and ZIP installation.

## Validation

`swift test --jobs 4` builds a focused, dependency-free package from the actual host/installer sources and runs lifecycle, renderer ownership, geometry, wire-validation, archive, and publisher-trust tests. It does not start the application or request its system permissions. The Xcode project remains the application build.

`examples/live-activity-extension/smoke.sh` loads the independently compiled example through the real runtime and renders it through the real activity host on two simulated display contexts. It checks native size-only updates as well as SwiftUI payload updates. This is a native rendering harness, not evidence of physical multi-monitor or system-gesture behavior.

Before release, exercise real mouse/trackpad browsing, VoiceOver actions, open/close album-art transitions, notification hover holds, OSD targeting on physical displays, fullscreen, and Reduced Motion in the running signed app. Production Developer ID/notarization acceptance also requires a signed distribution test; ad-hoc development fixtures do not establish it.
