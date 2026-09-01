#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MANUAL_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "manual_build.yml"


class ManualBuildWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = MANUAL_WORKFLOW.read_text(encoding="utf-8")
        inputs_start = cls.workflow.index("    inputs:\n")
        inputs_end = cls.workflow.index("\n# Least-privilege", inputs_start)
        cls.dispatch_inputs = cls.workflow[inputs_start:inputs_end]

    def test_dispatch_has_no_build_number_or_xcode_input(self) -> None:
        self.assertNotIn("build_number:", self.dispatch_inputs)
        self.assertNotIn("xcode_version:", self.dispatch_inputs)

    def test_authorization_uses_the_rerun_actor(self) -> None:
        self.assertIn("github.triggering_actor", self.workflow)

    def test_build_number_is_anchored_to_the_immutable_source(self) -> None:
        self.assertIn("source_sha", self.workflow)
        self.assertIn("github.run_number", self.workflow)
        self.assertIn("github.run_attempt", self.workflow)
        self.assertIn("extract_build_number.py", self.workflow)

    def test_manual_build_does_not_reserve_a_published_number(self) -> None:
        self.assertNotIn(".github/build-number", self.workflow)

    def test_reusable_defaults_are_not_repeated(self) -> None:
        build_job = self.workflow[self.workflow.index("  build:\n") :]
        self.assertNotIn("xcode_version:", build_job)
        self.assertNotIn("code_sign_identity:", build_job)


if __name__ == "__main__":
    unittest.main()
