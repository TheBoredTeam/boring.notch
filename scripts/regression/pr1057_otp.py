#!/usr/bin/env python3
"""Run OTP regression tests against the actual detector without launching the app.

Usage: python3 scripts/regression/pr1057_otp.py --work-dir /private/tmp/pr1057-otp
"""

import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    work_dir = args.work_dir.resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]

    # Run the XCTest cases as standalone preconditions without an XCTest host.
    # The production detector is compiled directly without rewriting.
    tests = (repo / "boringNotchTests/OTPDetectorTests.swift").read_text()
    (work_dir / "OTPDetectorTests.swift").write_text(
        tests.replace("@testable import boringNotch", "")
        .replace("import XCTest", "import Foundation")
        .replace(": XCTestCase", "")
        .replace("XCTAssertEqual", "requireEqual")
        .replace("XCTAssertNil", "requireNil")
    )
    (work_dir / "main.swift").write_text('''import Foundation

var assertionCount = 0
func requireEqual(_ actual: String?, _ expected: String?, _ message: String = "") {
    precondition(actual == expected, "\\(message): expected \\(expected ?? "nil"), got \\(actual ?? "nil")")
    assertionCount += 1
}
func requireNil(_ actual: String?, _ message: String = "") {
    requireEqual(actual, nil, message)
}

for text in ["Code 1234🔒", "🔒1234 code"] {
    let actual = OTPDetector.detect(in: text)
    precondition(actual == "1234", "Regression: \\(text)")
    print("\\(text) => \\(actual ?? "nil")")
}
for text in ["OTP fee $1234", "Code 1234%", "Code 1234:56", "Code 12:3456", "Promo code SAVE20"] {
    let actual = OTPDetector.detect(in: text)
    precondition(actual == nil, "False positive: \\(text)")
    print("\\(text) => \\(actual ?? "nil")")
}
OTPDetector.runSelfCheck()
print("Original DEBUG runSelfCheck passed")
let cases = OTPDetectorTests()
cases.testEmojiImmediatelyBeforeAndAfterDigits()
cases.testSupplementaryAndCombinedCharacterBoundaries()
cases.testBeginningAndEndOfString()
cases.testOrdinaryAndSplitNumericCodes()
cases.testCurrencyPercentageAndClockExclusions()
cases.testAlphanumericCodesRequireStrongContext()
print("Passed \\(assertionCount) standalone assertions from 6 regression tests")
''')
    executable = work_dir / "otp-regression"
    command = [
        "swiftc", "-D", "DEBUG", "-module-cache-path", str(work_dir / "module-cache"),
        str(repo / "boringNotch/helpers/OTPDetector.swift"),
        str(work_dir / "OTPDetectorTests.swift"), str(work_dir / "main.swift"),
        "-o", str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
