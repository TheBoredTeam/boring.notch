#!/usr/bin/env python3
"""Run extracted production Swift and XCTest with Foundation and minimal stand-ins."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEMP = Path("/private/tmp/pr1057-fixes-p7tundfo/preferences")
TEMP.mkdir(parents=True, exist_ok=True)
PLATFORM = Path(subprocess.check_output(["xcrun", "--show-sdk-platform-path"], text=True).strip())
FRAMEWORKS = PLATFORM / "Developer/Library/Frameworks"
SWIFT_SUPPORT = PLATFORM / "Developer/usr/lib"


def declaration(source, name):
    start = source.index(f"enum {name}")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


constants = (ROOT / "boringNotch/models/Constants.swift").read_text()
generic = (ROOT / "boringNotch/enums/generic.swift").read_text()
tests = (ROOT / "boringNotchTests/PreferenceCompatibilityTests.swift").read_text()
tests = tests.replace("@testable import boringNotch", "")
production = "\n".join(declaration(constants, name) for name in [
    "MediaControllerType", "SneakPeekStyle", "OptionKeyAction", "PreferenceCompatibility"
]) + "\n" + declaration(generic, "SliderColorEnum")
# Inject isolated suites and key namespaces; Foundation registration is process-wide.
bindings = re.findall(r'    static let (\w+) = (Key<Bool>\(PreferenceCompatibility[^\n]+)', constants)
assert len(bindings) == 5, "Expected all five production key initializers"
factories = []
for name, expression in bindings:
    expression = expression.replace("Key<Bool>(", "Key<Bool>(suite, ", 1)
    expression = re.sub(r'(from: "[^"]+")\)', r'\1, in: suite)', expression)
    expression = re.sub(r'"(\w+)"', r'"\\(namespace).\1"', expression)
    factories.append(f'"{name}": {{ suite, namespace in _ = {expression} }}')

standins = """
import Foundation
enum Defaults { protocol Serializable {} }
// Unrelated bundle-ID lookup dependency; enum raw-value decoding is unchanged.
struct YouTubeMusicConfiguration {
    static let `default` = Self()
    let bundleIdentifier = "test.youtube.music"
}
// Only the Defaults.Key fallback registration behavior is simulated.
struct Key<Value> {
    init(_ defaults: UserDefaults, _ name: String, default value: Value) {
        defaults.register(defaults: [name: value])
    }
}
"""
integration = r"""
extension PreferenceCompatibilityTests {
    func testProductionKeyInitializersMigrateBeforeRegistration() throws {
        let factories: [String: (UserDefaults, String) -> Void] = [FACTORIES]
        let scenarios: [(Bool?, Bool?)] = [(nil, nil), (false, nil), (true, nil),
                                          (true, false), (false, true)]
        for (legacy, current, fallback) in renamedKeys {
            for (oldValue, newValue) in scenarios {
                try withSuite { defaults, name in
                    let factory = try XCTUnwrap(factories[current])
                    let legacy = "\(name).\(legacy)"
                    let current = "\(name).\(current)"
                    if let oldValue { defaults.set(oldValue, forKey: legacy) }
                    if let newValue { defaults.set(newValue, forKey: current) }
                    for _ in 0..<2 {
                        factory(defaults, name)
                        XCTAssertEqual(defaults.bool(forKey: current), newValue ?? oldValue ?? fallback)
                        XCTAssertEqual(defaults.persistentDomain(forName: name)?[current] as? Bool,
                                       newValue ?? oldValue)
                    }
                }
            }
        }
    }
}
""".replace("FACTORIES", ",\n".join(factories))
runner = """
let suite = XCTestSuite(forTestCaseClass: PreferenceCompatibilityTests.self)
suite.run()
guard let run = suite.testRun, run.executionCount == 8 else { exit(2) }
exit(run.totalFailureCount == 0 ? 0 : 1)
"""
with tempfile.TemporaryDirectory(prefix="run-", dir=TEMP) as directory:
    work = Path(directory)
    source = work / "main.swift"
    source.write_text(standins + production + tests + integration + runner)
    env = os.environ | {"CLANG_MODULE_CACHE_PATH": str(work / "clang-cache")}
    print("Stand-ins: Defaults.Serializable, Defaults.Key registration, unrelated YouTube config; real Foundation UserDefaults.", flush=True)
    subprocess.run(["swiftc", "-F", str(FRAMEWORKS), "-I", str(SWIFT_SUPPORT),
                    "-L", str(SWIFT_SUPPORT), "-lXCTestSwiftSupport",
                    "-Xlinker", "-rpath", "-Xlinker", str(SWIFT_SUPPORT),
                    "-Xlinker", "-rpath", "-Xlinker", str(FRAMEWORKS.parent / "PrivateFrameworks"),
                    "-Xlinker", "-rpath", "-Xlinker", str(FRAMEWORKS),
                    "-module-cache-path", str(work / "swift-cache"),
                    str(source), "-o", str(work / "preferences")], check=True, env=env)
    subprocess.run([str(work / "preferences")], check=True, env=env)
