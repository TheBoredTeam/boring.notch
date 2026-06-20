#!/usr/bin/env python3

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path


VERSION_RE = re.compile(
    r"^[0-9]+[.][0-9]+([.][0-9]+)?(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$"
)
BUILD_NUMBER_RE = re.compile(r"^[0-9]+$")
VALID_UPDATE_CHANNELS = {"stable", "beta", "dev"}


def validate_version(version: str | None) -> None:
    if not version:
        return
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"Invalid marketing version: {version}")


def validate_build_number(build_number: str) -> None:
    if not BUILD_NUMBER_RE.fullmatch(build_number):
        raise ValueError(f"Invalid build number: {build_number}")


def validate_update_channel(update_channel: str | None) -> None:
    if not update_channel:
        return
    if update_channel not in VALID_UPDATE_CHANNELS:
        valid = ", ".join(sorted(VALID_UPDATE_CHANNELS))
        raise ValueError(f"Invalid update channel: {update_channel}; expected one of: {valid}")


def replace_build_setting(text: str, key: str, value: str) -> tuple[str, int]:
    pattern = re.compile(rf"({re.escape(key)}\s*=\s*)[^;]+;")
    return pattern.subn(lambda match: f"{match.group(1)}{value};", text)


def stamp_pbxproj(pbxproj_path: Path, version: str | None, build_number: str) -> None:
    text = pbxproj_path.read_text(encoding="utf-8")

    if version:
        text, version_count = replace_build_setting(text, "MARKETING_VERSION", version)
        if version_count == 0:
            raise ValueError(f"No MARKETING_VERSION settings found in {pbxproj_path}")

    text, build_count = replace_build_setting(text, "CURRENT_PROJECT_VERSION", build_number)
    if build_count == 0:
        raise ValueError(f"No CURRENT_PROJECT_VERSION settings found in {pbxproj_path}")

    pbxproj_path.write_text(text, encoding="utf-8")


def stamp_info_plist(info_plist_path: Path, update_channel: str) -> None:
    with info_plist_path.open("rb") as plist_file:
        plist = plistlib.load(plist_file)

    plist["BNUpdateChannel"] = update_channel

    with info_plist_path.open("wb") as plist_file:
        plistlib.dump(plist, plist_file, sort_keys=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Stamp Xcode project version/build settings and optional app update channel."
    )
    parser.add_argument("--pbxproj", required=True, type=Path)
    parser.add_argument("--version", default="")
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--info-plist", type=Path)
    parser.add_argument("--update-channel", default="")
    args = parser.parse_args(argv)

    try:
        validate_version(args.version)
        validate_build_number(args.build_number)
        validate_update_channel(args.update_channel)
        stamp_pbxproj(args.pbxproj, args.version or None, args.build_number)
        if args.update_channel:
            if args.info_plist is None:
                raise ValueError("--info-plist is required when --update-channel is set")
            stamp_info_plist(args.info_plist, args.update_channel)
    except Exception as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    version_label = args.version or "(unchanged)"
    channel_label = args.update_channel or "(unchanged)"
    print(
        f"Stamped version={version_label} build={args.build_number} "
        f"update_channel={channel_label}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
