# Evening diary validation

The diary is optional and only follows evening review. Settings live under **Planning & Review**. The default destination is **Documents/Boring Notch Diary**; use **Allow Folder Access…** once to grant macOS access. Choosing Documents creates that subfolder; choosing another folder uses it directly. The selected folder is retained with a security-scoped bookmark.

Entries preserve the exact Markdown source in `YYYY-MM-DD.md`. Additional entries on the same day receive numbered suffixes; existing files are never replaced. Empty or whitespace-only entries finish the review without writing a file or showing the filing animation. Unsaved text stays in memory while returning to the review page; it is not a crash-recovery draft.

## Automated checks

```sh
swift test
bash validation/daily-conclusion/run.sh
```

The second command compiles the production views and manager into a temporary AppKit executable. It uses synthetic reminders, isolated UserDefaults suites, and a temporary diary directory. It checks keyboard focus, hover-dismissal protection, back-navigation draft retention, missing-permission errors, duplicate submission, saving, filing/farewell sequencing, cleanup, empty entries, and morning planning. Temporary preferences, files, and executable are removed on completion. It does not change the installed app or user reminder data.

Optional native captures (synthetic content only):

```sh
mkdir -p /tmp/diary-native-captures
DIARY_SMOKE_CAPTURES=/tmp/diary-native-captures bash validation/daily-conclusion/run.sh
```

## Sandboxed app check

Use a signed Debug app for the macOS folder-grant checks; the standalone smoke executable is not sandboxed.

1. Open Planning & Review. Enable conclusions and allow the default diary folder. Confirm Calendar no longer contains workflow settings.
2. Open evening review. Check the existing reminder layout and completion toggles. Choose Next, type Markdown, paste multiple paragraphs, scroll, undo, and use an input method if available. Moving the pointer out must not close the editor.
3. Return to review and choose Next again; the draft should remain. End Review: observe the monochrome card enter the folder, the folder slide below the window, then the existing farewell and close. Check the Markdown file matches the input.
4. Relaunch the app and save another entry without granting the folder again. Check changing the folder works and existing files are preserved.
5. Try blank and whitespace-only drafts: no new file and no folder animation. Disable conclusions: evening review finishes directly. Morning planning remains unchanged.
6. Remove access or move the chosen folder. A failed save must retain the draft and offer a retry after selecting the folder again.
7. Enable macOS Reduce Motion. Saving and completion should work without the paper/folder movement.

The native filing artwork is implemented directly in SwiftUI; no third-party artwork or reference-site code is copied.
