#!/usr/bin/env python3
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

"""Build independent, signed native tab fixtures; never modifies an app install."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:3])} failed:\n{result.stdout}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "dist")
    parser.add_argument("--providers", type=int, default=50, choices=range(1, 51), metavar="1..50")
    parser.add_argument("--jobs", type=int, default=4, choices=range(1, 9), metavar="1..8")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parent / "TabStress.m"
    architecture = os.uname().machine
    with tempfile.TemporaryDirectory(prefix=".build-", dir=output) as temporary:
        staging = Path(temporary)

        def build(number):
            token = f"p{number:03d}"
            identifier = f"org.example.boringnotch.tab-stress.{token}"
            bundle = staging / f"{identifier}.bnplugin"
            executable = bundle / "Contents/MacOS/TabStress"
            executable.parent.mkdir(parents=True)
            resources = bundle / "Contents/Resources"
            resources.mkdir()
            run("xcrun", "clang", "-dynamiclib", "-fobjc-arc", "-O1", "-Wall", "-Wextra",
                "-Wno-unused-parameter", "-mmacosx-version-min=14.0", "-arch", architecture,
                f"-DBN_PROVIDER_INDEX={number}", f"-DBN_PROVIDER_TOKEN={token}",
                f'-DBN_PROVIDER_ID="{identifier}"', "-framework", "AppKit", "-framework", "Foundation",
                str(source), "-o", str(executable))
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": identifier, "CFBundleName": f"Tab Stress {number:03d}",
                "CFBundleExecutable": "TabStress", "CFBundlePackageType": "BNDL",
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0"
            }))
            (resources / "manifest.json").write_text(json.dumps({
                "id": identifier, "name": f"Tab Stress {number:03d}", "version": "1.0.0",
                "apiVersion": 1, "activation": "always", "capabilities": ["tabs"]
            }, indent=2) + "\n")
            run("codesign", "--force", "--sign", "-", str(bundle))
            run("codesign", "--verify", "--strict", "--all-architectures", str(bundle))
            destination = output / bundle.name
            if destination.exists():
                shutil.rmtree(destination)
            bundle.rename(destination)
            return {"id": identifier, "bundle": destination.name,
                    "firstTab": (number - 1) * 8 + 1, "lastTab": number * 8}

        # Hand off a real one-bundle ZIP early, while the remaining images build.
        first = build(1)
        zip_path = output / "TabStress-p001-development.zip"
        if zip_path.exists():
            zip_path.unlink()
        run("ditto", "-c", "-k", "--keepParent", str(output / first["bundle"]), str(zip_path))
        print(f"FIRST_ZIP={zip_path}", flush=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
            providers = [first] + list(executor.map(build, range(2, args.providers + 1)))
        (output / "index.json").write_text(json.dumps({
            "architecture": architecture, "providerCount": len(providers), "tabCount": len(providers) * 8,
            "regularTabs": len(providers) * 8, "compactTabs": len(providers) * 4,
            "providers": providers
        }, indent=2) + "\n")
        print(f"Built {len(providers)} signed {architecture} bundles, {len(providers) * 8} tabs: {output}", flush=True)


if __name__ == "__main__":
    main()
