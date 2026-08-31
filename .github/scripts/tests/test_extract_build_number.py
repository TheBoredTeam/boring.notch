#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from extract_build_number import extract_build_number  # noqa: E402


PROJECT = """
buildSettings = {
    CURRENT_PROJECT_VERSION = 272;
    PRODUCT_BUNDLE_IDENTIFIER = theboringteam.boringnotch;
};
buildSettings = {
    CURRENT_PROJECT_VERSION = 272;
    PRODUCT_BUNDLE_IDENTIFIER = theboringteam.boringnotch;
};
buildSettings = {
    CURRENT_PROJECT_VERSION = 900;
    PRODUCT_BUNDLE_IDENTIFIER = theboringteam.boringnotch.BoringNotchXPCHelper;
};
buildSettings = {
    CURRENT_PROJECT_VERSION = 1;
    PRODUCT_BUNDLE_IDENTIFIER = com.qareai.boringNotchTests;
};
"""


class ExtractBuildNumberTests(unittest.TestCase):
    def test_extracts_the_app_target_build(self) -> None:
        self.assertEqual(
            extract_build_number(PROJECT, "theboringteam.boringnotch"),
            "272",
        )

    def test_rejects_disagreeing_app_configurations(self) -> None:
        project = PROJECT.replace(
            "CURRENT_PROJECT_VERSION = 272;",
            "CURRENT_PROJECT_VERSION = 271;",
            1,
        )
        with self.assertRaisesRegex(ValueError, "disagree"):
            extract_build_number(project, "theboringteam.boringnotch")

    def test_rejects_missing_app_target(self) -> None:
        with self.assertRaisesRegex(ValueError, "No build settings"):
            extract_build_number(PROJECT, "missing.bundle")

    def test_rejects_non_integer_app_build(self) -> None:
        project = PROJECT.replace(
            "CURRENT_PROJECT_VERSION = 272;",
            "CURRENT_PROJECT_VERSION = beta;",
        )
        with self.assertRaisesRegex(ValueError, "positive integer"):
            extract_build_number(project, "theboringteam.boringnotch")


if __name__ == "__main__":
    unittest.main()
