#!/usr/bin/env python3
"""Render synthetic formulas using production code and the app's sandbox entitlements."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROBE = r'''
import AppKit
import SwiftUI

@main
struct MathProbe {
    @MainActor
    static func main() async {
        _ = NSApplication.shared
        let source = #"\[\mathbf x\xrightarrow{\text{encoder}}\boldsymbol\mu_\phi(\mathbf x)\] \[D_{\mathrm{KL}}\left[\underbrace{q_\phi(\mathbf z\mid\mathbf x)}_{\text{predicted codes}}\middle\|\underbrace{p(\mathbf z)}_{\text{prior}}\right]\]"#
        let document = CodexMathDocument(source: source)
        guard document.equations.count == 2 else { fatalError("Math delimiter parsing failed") }
        for equation in document.equations.values {
            guard let image = await CodexMathImage.render(equation),
                  let pixels = ImageRenderer(content: image).cgImage,
                  pixels.width > 10, pixels.height > 5 else {
                fatalError("Sandboxed math rendering failed")
            }
        }
        print("Sandboxed math probe: both formulas rendered.")
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    products = args.derived_data / "Build/Products/Debug"
    app = products / "boringNotch.app"
    includes = args.derived_data / "SourcePackages/checkouts/swift-cmark/src/include"
    with tempfile.TemporaryDirectory(prefix="boring-notch-math-probe-") as directory:
        scratch = Path(directory)
        host = scratch / "MathProbe.app"
        contents = host / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        # Match the existing product container without reading or writing preferences.
        probe_info = {key: info[key] for key in ["CFBundleIdentifier", "CFBundlePackageType"]}
        probe_info.update(CFBundleExecutable="MathProbe", CFBundleName="MathProbe", LSUIElement=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps(probe_info))
        bundle = "MathJaxSwift_MathJaxSwift.bundle"
        subprocess.run(["ditto", str(app / "Contents/Resources" / bundle), str(contents / "Resources" / bundle)], check=True)
        source = scratch / "main.swift"
        source.write_text(PROBE)
        binary = contents / "MacOS/MathProbe"
        subprocess.run([
            "swiftc", "-parse-as-library", "-module-cache-path", "/tmp/boring-notch-swift-module-cache",
            "-I", str(products), "-I", str(includes),
            *[str(products / name) for name in ["MathJaxSwift.o", "SwiftDraw.o", "SwiftDrawDOM.o", "cmark-gfm.o"]],
            str(ROOT / "boringNotch/features/CodexNotifications/Rendering/CodexMathDocument.swift"),
            str(ROOT / "boringNotch/features/CodexNotifications/Rendering/CodexMathImage.swift"),
            str(source), "-o", str(binary),
        ], check=True)
        signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True)
        entitlements = plistlib.loads(signed.stdout)
        assert entitlements.get("com.apple.security.app-sandbox") is True
        entitlements_file = scratch / "probe.entitlements"
        entitlements_file.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(entitlements_file), str(host)], capture_output=True, check=True)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
