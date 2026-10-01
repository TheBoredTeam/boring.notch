# Tab scale validation — 2026-09-29

Validated locally on Apple silicon, macOS 26.5.2, using an isolated Debug host.
The production app, user extensions, and user license storage were not modified.

## Coverage

| Layer | Load | Verified |
| --- | --- | --- |
| Registry tests | 125 providers, eight tabs each: 1,000 total | Namespaces, deterministic order, eligibility, lookup, provider removal, unchanged-publication suppression, 5,000 metadata updates, and no eager content creation. |
| Native mounting tests | All 400 eligible Compact tabs selected sequentially | One controller alive per selection, zero after removal, 336 × 132-point bounds, and no focus theft. |
| Independent bundle smoke | 50 separately signed native images, 400 Regular / 200 Compact tabs | Public ABI, distinct Objective-C classes, presentation contexts, descriptor withdrawal/restoration, and 102 balanced controller lifetimes. |
| Running application | 50 installed fixture bundles, plus Focus Timer and licensed Lock Screen | 403 total Regular entries and 203 Compact entries, overflow scrolling, beginning/middle/end selection, automatic scrolling to the selected tab, and bounded content. |

One fixture ZIP was installed through Settings. The remaining fixtures were
seeded into the disposable test directory and loaded on restart. The fixture
limit stayed at eight tabs per provider throughout.

## Live observations and corrections

- The original strip eagerly constructed every button and repeatedly validated
  SF Symbols. The updated strip creates nearby buttons lazily, snapshots its
  items once per render, and stores resolved symbols with each registration.
- Probe 400 rendered in Regular mode at 578 × 132 points on the test display.
  Probe 399 rendered in Compact mode at exactly 336 × 132 points. Regular-only
  Probe 400 was absent from the Compact menu; switching modes returned Home.
- Withdrawing the selected provider removed its four Compact tabs immediately:
  200 fixture entries became 196, and selection returned Home. Restoring the
  descriptors did not instantiate hidden controllers. That process recorded
  five created and five released fixture controllers.
- Both standard placements were tested: embedded tabs and the new optional
  floating pill. Moving the strip preserved Probe 400's selection, geometry,
  and controller identity. Compact remained floating independently.
- The final coexistence check verified Lock Screen's local test license while
  all 50 fixture providers were loaded. It exercised both presentations and
  finished with three created / three released fixture controllers and none
  remaining alive. An earlier temporary launcher used an invalid test-suite
  prefix; that launcher was corrected before this coexistence check.
- All disposable bundles were removed from the installed test directory after
  validation. Focus Timer and Lock Screen remain separate runtime bundles.

The native overflow menu stayed open during scrolling. Finding one item among
hundreds remains cumbersome: tab search, pinning, grouping, and recents are not
implemented by this change.

## Measurements and reproduction

The integrated suite passed 113 tests after the catalog changes; the complete
Debug application build also succeeded. Existing application concurrency and
toolbar warnings remain outside this change.

One local test run registered 1,000 tabs in 63.9 ms, performed 200 eligibility
filters in 95.7 ms, and performed 40,000 lookups in 117.7 ms. These are
informational measurements without timing assertions, not a frame-rate or
third-party extension performance guarantee. Fixtures intentionally have no
background timer per tab. Real extension background work is independent of
whether a tab is mounted.

```sh
# From the host repository:
swift test --filter ExtensionTabScaleTests

# From examples/tab-stress:
python3 build.py
bash smoke.sh
python3 summarize.py /tmp/boring-tab-scale/controllers.jsonl --pid <host-pid>
```

The GUI checks covered one display. Physical lock/unlock, multiple simultaneous
displays, and arbitrary third-party extension workloads were not exercised in
this scale run.
