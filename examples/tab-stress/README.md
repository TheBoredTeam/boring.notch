# Native tab scale fixture

This development-only fixture builds **50 independent signed bundles with eight
tabs each**: Probe 001 through Probe 400. All 400 support regular mode; the 200 odd
probes also explicitly support compact mode. Even probes omit `presentations`
to exercise the regular-only default. Each bundle implements the public C ABI
in Objective-C and receives unique provider-specific class names, so loading all
50 images together does not collide in the Objective-C runtime. There is no
shared extension source compiled into Boring Notch and no timer per tab.

```sh
python3 build.py
bash smoke.sh
```

`dist/index.json` lists every bundle. The default build produces current-machine
architecture binaries, ad-hoc signs and verifies each bundle, and creates
`dist/TabStress-p001-development.zip` containing exactly one installable bundle.
The remaining bundles live directly under `dist/`; the host does not support a
multi-extension ZIP. Use an isolated Debug app with
`BN_ALLOW_DEVELOPMENT_EXTENSIONS=1`. These are development artifacts, not
Developer ID/notarized releases. The build does not install or launch anything.

The smoke loads all 50 images through the real host runtime and verifies 400/200
registrations create zero view controllers. It requests one controller per
presentation/provider, mounts only two selected tabs through the actual native
bridge, checks class uniqueness, bounds, regular-only rejection, descriptor
withdrawal/restore, and matching controller create/deinit events. Its preferences,
telemetry, and offscreen test windows are isolated from a running host.

Every instance and controller lifecycle writes JSON Lines to
`/tmp/boring-tab-scale/controllers.jsonl` by default. Set `BN_TAB_STRESS_LOG` to
another file before launching the test host; an empty value disables logging.
Each controller record includes a unique controller ID, process ID, provider,
tab ID/title, presentation, display ID, and supplied content size. Registration
logs only `instance.create`: `controller.create` appears only when the factory
is requested. `controller.deinit` carries the same ID after release. The fixture
never logs user content.

```sh
python3 summarize.py
python3 summarize.py /tmp/boring-tab-scale/controllers.jsonl --pid 12345
```

Expect no live probe controllers while Home/Shelf is selected, and one per
display showing a probe. Transition overlap can temporarily keep the old
controller alive. Use a single process ID when evaluating a log spanning host
relaunches. Abrupt process exit can omit deinit callbacks; balance only controllers
that were actually unmounted while the process stayed alive.

Each provider's native settings has **Withdraw eight tabs** and **Restore eight
tabs** actions. They send `tabs.changed` through the public callback and can test
selected-tab fallback without disabling or replacing the bundle. The same
fixture-only actions are available through ABI events `stress.tabs.withdraw` and
`stress.tabs.restore` for the smoke harness. Withdrawal affects only that provider.
