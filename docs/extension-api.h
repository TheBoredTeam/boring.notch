// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Boring Notch extension ABI v1. All entry points and callbacks are main-thread
 * only. This header does not depend on the app's Swift module or compiler ABI.
 * Context belongs to the host: return it unchanged and never dereference it.
 * Stop callbacks, tasks and windows before destroy returns. Swift/AppKit view
 * state may outlive the instance during UI teardown; it must remain safe then.
 */
typedef void (*BNExtensionCommand)(void *context, const char *command, double value);

/* Required exports. The instance pointer belongs to the extension. */
void *bn_extension_create_v1(void *context, BNExtensionCommand command);
void bn_extension_destroy_v1(void *instance);
/* JSON bytes are borrowed for this call only. Unknown fields must be ignored.
 * activitySurfaces advertises the supported native surfaces, currently
 * ["desktop","lockScreen"]. If absent, assume desktop only. Check support
 * before publishing lockScreen content: older v1 hosts ignore unknown fields.
 * presentationAllowed reports the routine snapshot lifecycle gate; it does not
 * remove registered live activities.
 */
void bn_extension_update_v1(void *instance, const uint8_t *json, intptr_t byte_count);
void bn_extension_event_v1(void *instance, const char *event);
/* Borrowed NSViewController pointer, valid until destroy. Host retains it while
 * displayed. NULL is permitted when there is no settings UI. */
void *bn_extension_settings_v1(void *instance);

/* Required when manifest capabilities includes "liveActivities".
 * Borrowed, NUL-terminated UTF-8 JSON, at most 65,536 bytes excluding the NUL.
 * Host copies it before the next extension call. Return {"activities":[]} to
 * withdraw all activities; NULL is an invalid snapshot.
 *
 * {"activities":[{"id":"focus-1","label":"Focus timer",
 *   "relevance":"active","expiresAt":1790684100,"displays":["display-uuid"]}]}
 *
 * At most 16 activities. IDs are unique local IDs matching
 * [A-Za-z0-9][A-Za-z0-9._-]*, at most 100 UTF-8 bytes. The host namespaces IDs
 * with the signed manifest identity. Labels are nonempty, at most 256 bytes.
 * Optional relevance is passive, active (default), or timeSensitive; the host
 * maps it to bounded priorities. Extensions cannot claim system interruption.
 * Optional expiresAt is finite UNIX time in seconds. Optional displays is at
 * most 32 nonempty display IDs, each at most 128 bytes; omit for all displays.
 * An empty displays array means no eligible displays.
 * Optional surface is "desktop" (default) or "lockScreen". Desktop content is
 * never promoted to the secure locked window. Lock-screen regions are
 * noninteractive and hidden while asleep or the session is inactive. Publish
 * only content intended to be visible on a locked Mac.
 *
 * Publish a change by command(context, "activities.changed", 0). The host
 * reconciles on its next main runloop turn. Keep an ID stable for content
 * updates; issue a new ID for a new activity. Updating an existing observable
 * view model does not require recreating controllers.
 */
const char *bn_extension_activities_v1(void *instance);

enum BNExtensionActivityRegion {
    BN_EXTENSION_ACTIVITY_LEADING = 0,
    BN_EXTENSION_ACTIVITY_TRAILING = 1
};

/* Return a NEW +1 retained NSViewController for every call, including calls for
 * the same activity on different displays. Host consumes that retain. NULL
 * means an empty region. activity_id/display_id strings are borrowed for this
 * call only; display_id may be NULL. Controllers may be NSHostingController
 * instances and should retain their observable state independently of instance.
 * Use preferredContentSize for an ideal content size. The host owns camera safe
 * space, side margins, width limits and animations; supply only side content.
 */
void *bn_extension_activity_view_v1(void *instance, const char *activity_id,
                                   int32_t region, const char *display_id);

/* Required when manifest capabilities includes "tabs". Tabs are independent of
 * liveActivities; a bundle can provide either capability or both.
 * Borrowed NUL-terminated UTF-8 JSON, at most 65,536 bytes. Same lifetime and
 * main-thread rules as activities_v1. Return {"tabs":[]} to withdraw all tabs.
 *
 * {"tabs":[{"id":"focus","title":"Focus","symbol":"timer",
 *   "presentations":["regular","compact"]}]}
 *
 * At most 8 tabs per provider. IDs follow the activity local-ID grammar.
 * title is nonblank and at most 64 UTF-8 bytes. symbol is an SF Symbol name at
 * most 128 UTF-8 bytes; unavailable symbols render a host fallback icon.
 * Optional iconPNG is base64-encoded static PNG artwork, at most 16,384 UTF-8
 * bytes encoded and 128x128 pixels (both dimensions must be positive). Exactly
 * one complete PNG is allowed: no APNG, trailing data, URLs or data-URL prefix.
 * The host renders its alpha mask as a template in the tab strip and overflow,
 * tinting it for selection/appearance. Keep symbol for older-host compatibility.
 * Missing, malformed, oversized or unsupported artwork falls back to symbol
 * without removing the tab. Decoded icons are cached; icon metadata changes
 * preserve mounted controller identity. The entire snapshot still fits 65,536
 * bytes, including base64 artwork. No binary ABI version change is needed.
 * Optional presentations is a nonempty, unique array of "regular"/"compact".
 * Omitting it means ["regular"], preserving existing bundles. Compact support
 * requires both explicit declaration and tab_view_v2 below; it is never inferred
 * from a preferred size or supplied by scaling a regular controller. The host
 * hides unsupported tabs in the current presentation and falls back to Home if
 * the selected tab becomes unavailable. Tabs never appear on the lock screen.
 * The signed manifest ID supplies the namespace. Keep IDs stable across title
 * and icon changes. command(context, "tabs.changed", 0) requests reconciliation
 * on the next main runloop turn. Registration never steals the selected tab.
 */
const char *bn_extension_tabs_v1(void *instance);

/* NEW +1 retained NSViewController for every request/display. NULL produces an
 * unavailable-content placeholder. The host consumes the retain and owns tab
 * chrome, navigation, and available bounds. The extension owns the complete
 * native content layout, controls, state, and live updates. Views may use AppKit
 * or SwiftUI and must remain safe through removal/destroy transitions. The host
 * mounts selected content only; use native visibility lifecycle to suspend work.
 * This legacy factory supplies REGULAR desktop content only. It remains useful
 * for bundles supporting hosts predating tab_view_v2. A new host prefers v2 when
 * present and does not fall back to v1 after a v2 NULL result. Export at least
 * one of tab_view_v1 or tab_view_v2 when declaring the tabs capability.
 * No host Swift module, extension source, or static linking is required.
 */
void *bn_extension_tab_view_v1(void *instance, const char *tab_id,
                              const char *display_id);

/* Optional context-aware factory, REQUIRED to opt in to compact tabs. Same
 * main-thread and NEW +1 controller ownership rules as tab_view_v1. context_json
 * is borrowed NUL-terminated UTF-8 JSON; copy/decode during this call and ignore
 * unknown fields. NULL means unavailable content, not a request for v1 fallback.
 *
 * {"presentation":"compact","displayID":null,
 *  "contentSize":{"width":336,"height":132}}
 *
 * presentation is "regular" or "compact"; displayID is a string or null.
 * contentSize supplies the actual finite content bounds in macOS points. Decode
 * and validate these values. The dimensions above are an example, not a fixed
 * ABI constant. Author intentional layouts for every declared presentation.
 * Both may share one observable model; returning a controller for another mode
 * or scaling the regular UI is not a compact implementation.
 *
 * Host-owned chrome and camera clearance sit outside these bounds. The host
 * clips the native view and ignores preferred size for tab sizing. This factory
 * has no API for resizing the notch or detaching content into another window.
 * It remounts content when presentation, display, or available bounds change;
 * ordinary metadata updates preserve the current controller. Retain navigation,
 * progress, and other durable state in the extension model across remounts.
 */
void *bn_extension_tab_view_v2(void *instance, const char *tab_id,
                              const char *context_json);

#ifdef __cplusplus
}
#endif
