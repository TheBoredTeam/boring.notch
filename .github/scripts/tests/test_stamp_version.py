#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from stamp_version import (  # noqa: E402
    stamp_info_plist,
    stamp_pbxproj,
    validate_build_number,
    validate_update_channel,
    validate_version,
)


class StampVersionTests(unittest.TestCase):
    def test_stamps_all_project_versions_and_build_numbers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pbxproj = Path(tmp) / "project.pbxproj"
            pbxproj.write_text(
                """
                MARKETING_VERSION = "2.8-beta.0";
                CURRENT_PROJECT_VERSION = 272;
                MARKETING_VERSION = 2.7.3;
                CURRENT_PROJECT_VERSION = 271;
                """,
                encoding="utf-8",
            )

            stamp_pbxproj(pbxproj, "2.8.0", "273")

            contents = pbxproj.read_text(encoding="utf-8")
            self.assertEqual(contents.count("MARKETING_VERSION = 2.8.0;"), 2)
            self.assertEqual(contents.count("CURRENT_PROJECT_VERSION = 273;"), 2)

    def test_can_leave_marketing_version_unchanged_for_nightly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pbxproj = Path(tmp) / "project.pbxproj"
            pbxproj.write_text(
                """
                MARKETING_VERSION = "2.8-beta.0";
                CURRENT_PROJECT_VERSION = 272;
                """,
                encoding="utf-8",
            )

            stamp_pbxproj(pbxproj, None, "300")

            contents = pbxproj.read_text(encoding="utf-8")
            self.assertIn('MARKETING_VERSION = "2.8-beta.0";', contents)
            self.assertIn("CURRENT_PROJECT_VERSION = 300;", contents)

    def test_stamps_update_channel_in_info_plist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            info_plist = Path(tmp) / "Info.plist"
            with info_plist.open("wb") as plist_file:
                plistlib.dump({"BNUpdateChannel": "stable"}, plist_file)

            stamp_info_plist(info_plist, "beta")

            with info_plist.open("rb") as plist_file:
                self.assertEqual(plistlib.load(plist_file)["BNUpdateChannel"], "beta")

    def test_rejects_invalid_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "Invalid marketing version"):
            validate_version("version 2")
        with self.assertRaisesRegex(ValueError, "Invalid build number"):
            validate_build_number("27a")
        with self.assertRaisesRegex(ValueError, "Invalid update channel"):
            validate_update_channel("canary")


if __name__ == "__main__":
    unittest.main()
