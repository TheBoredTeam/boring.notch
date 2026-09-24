# Evening diary validation

The diary is optional and only follows evening review. Settings live under **Planning & Review**. The default destination is **Documents/Boring Notch Diary**; use **Allow Folder Access…** once to grant macOS access. Choosing Documents creates that subfolder; choosing another folder uses it directly. The selected folder is retained with a security-scoped bookmark.

Entries preserve the exact Markdown source in `YYYY-MM-DD.md`. Additional entries on the same day receive numbered suffixes; existing files are never replaced. Empty or whitespace-only entries finish the review without writing a file or showing the filing animation. Unsaved text stays in memory while returning to the review page; it is not a crash-recovery draft.

## Automated checks

```sh
swift test
DIARY_BUILD_PRODUCTS=/tmp/boring-diary-build/Build/Products/Debug bash validation/daily-conclusion/run.sh
```

Build the Debug app first and point `DIARY_BUILD_PRODUCTS` at its products directory. The second command compiles the production SkyLight window, views, and manager into a temporary AppKit executable. It uses synthetic reminders, isolated UserDefaults suites, and a temporary diary directory. It checks keyboard focus, hover dismissal and draft restoration, back-navigation draft retention, missing-permission errors, duplicate submission, saving, filing/farewell sequencing, cleanup, empty entries, and morning planning. Temporary preferences, files, and executable are removed on completion. It does not change the installed app or user reminder data.

Optional native captures (synthetic content only):

```sh
mkdir -p /tmp/diary-native-captures
DIARY_SMOKE_CAPTURES=/tmp/diary-native-captures DIARY_BUILD_PRODUCTS=/tmp/boring-diary-build/Build/Products/Debug bash validation/daily-conclusion/run.sh
```

## Sandboxed app check

Use a signed Debug app for the macOS folder-grant checks; the standalone smoke executable is not sandboxed.
Launch the Debug app with `--preview-evening-review` to immediately open evening review
with the diary enabled in memory, without changing the stored schedule or diary toggle.
Completing this review still records the normal evening completion.

1. Open Planning & Review. Enable conclusions and allow the default diary folder. Confirm Calendar no longer contains workflow settings.
2. Hover the upper notch and then the lower reminder area; both must open evening review, including after folding it and while another OSD briefly covers the prompt. The shell should resize; the reminder must not slide up separately. Open evening review. Check the existing reminder layout and completion toggles. Choose Next, type Markdown, paste multiple paragraphs, scroll, undo, and use an input method if available. Moving the pointer out must fold the window; hovering again must restore the editor and draft.
3. Return to review and choose Next again; the draft should remain. End Review: observe the monochrome card enter the folder, the folder slide below the window without changing color, then the existing farewell and close. The farewell must start only after the folder has exited. Check the Markdown file matches the input.
4. Relaunch the app and save another entry without granting the folder again. Check changing the folder works and existing files are preserved.
5. Try blank and whitespace-only drafts: no new file and no folder animation. Disable conclusions: evening review finishes directly. Morning planning remains unchanged.
6. Remove access or move the chosen folder. A failed save must retain the draft and offer a retry after selecting the folder again.
7. Enable macOS Reduce Motion. Saving and completion should work without the paper/folder movement.

The native filing artwork is implemented directly in SwiftUI; no third-party artwork or reference-site code is copied.

## Avoid overlapping app instances during manual testing

The installed app and Debug app have the same bundle ID. Codex notification hooks
open that ID, so LaunchServices can start a different registered copy over the test
window. The taller review window then receives lower-area hover while the installed
notch receives upper-area hover. This can look like a routing bug even when each
process routes correctly.

After building and signing the Debug app, run:

```sh
python3 validation/daily-conclusion/launch-debug.py
```

Set `DIARY_DEBUG_APP` if the signed source bundle is elsewhere. The script copies
it to a stable DerivedData test location, closes matching Boring Notch processes
using `proc_pidpath` (macOS `ps -o comm` can truncate paths), and temporarily
unregisters other copies of this bundle ID. It registers and launches the feature
app, exercises a bundle-ID open, and requires exactly one process. It does not
edit application preferences or the notification hook. Apps in `/tmp` did not
appear as candidates in the LaunchServices lookup during this investigation.

To return normal bundle-ID launches to the installed app after testing:

```sh
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$HOME/Library/Developer/Xcode/DerivedData/boring-notch-evening-diary/Build/Products/Debug/boringNotch.app"
"$lsregister" -f /Applications/boringNotch.app
```

Quit the Debug instance before opening the installed app.
