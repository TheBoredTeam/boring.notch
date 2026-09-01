#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


BUILD_SETTINGS_RE = re.compile(
    r"^\s*buildSettings\s*=\s*\{(?P<body>.*?)^\s*\};",
    re.MULTILINE | re.DOTALL,
)


def _setting(block: str, name: str) -> str | None:
    match = re.search(
        rf"^\s*{re.escape(name)}\s*=\s*(?P<value>[^;]+)\s*;",
        block,
        re.MULTILINE,
    )
    if match is None:
        return None
    return match.group("value").strip().strip('"')


def extract_build_number(project_text: str, bundle_identifier: str) -> str:
    """Return the one positive integer used by all matching target configurations."""
    matching_blocks = [
        match.group("body")
        for match in BUILD_SETTINGS_RE.finditer(project_text)
        if _setting(match.group("body"), "PRODUCT_BUNDLE_IDENTIFIER")
        == bundle_identifier
    ]
    if not matching_blocks:
        raise ValueError(
            f"No build settings found for bundle identifier {bundle_identifier}"
        )

    build_numbers: list[str] = []
    for block in matching_blocks:
        build_number = _setting(block, "CURRENT_PROJECT_VERSION")
        if build_number is None or re.fullmatch(r"[1-9][0-9]*", build_number) is None:
            raise ValueError(
                "CURRENT_PROJECT_VERSION must be a positive integer in every "
                f"configuration for {bundle_identifier}"
            )
        build_numbers.append(build_number)

    unique_build_numbers = set(build_numbers)
    if len(unique_build_numbers) != 1:
        values = ", ".join(sorted(unique_build_numbers, key=int))
        raise ValueError(
            f"CURRENT_PROJECT_VERSION values disagree for {bundle_identifier}: {values}"
        )

    return build_numbers[0]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read the agreed app-target build number from an Xcode project."
    )
    parser.add_argument("--pbxproj", required=True, type=Path)
    parser.add_argument("--bundle-identifier", required=True)
    args = parser.parse_args(argv)

    try:
        project_text = args.pbxproj.read_text(encoding="utf-8")
        print(extract_build_number(project_text, args.bundle_identifier))
    except Exception as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
