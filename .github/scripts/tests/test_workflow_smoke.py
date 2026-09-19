#!/usr/bin/env python3
"""Structural smoke test for the release pipeline workflows.

The workflow YAML cannot execute under unit test; these checks only pin the
load-bearing invariants that keep the pipeline safe: what triggers it, who
may run it, and which trusted code it executes. Everything else is
intentionally left to real workflow runs.
"""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


class WorkflowSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.release = (REPOSITORY_ROOT / ".github" / "workflows" / "release.yml").read_text(
            encoding="utf-8"
        )
        self.nightly = (REPOSITORY_ROOT / ".github" / "workflows" / "nightly.yml").read_text(
            encoding="utf-8"
        )
        self.build_reusable = (
            REPOSITORY_ROOT / ".github" / "workflows" / "build_reusable.yml"
        ).read_text(encoding="utf-8")
        self.manual_build = (REPOSITORY_ROOT / ".github" / "workflows" / "manual_build.yml").read_text(
            encoding="utf-8"
        )

    def test_release_is_dispatched_with_a_version_against_main(self) -> None:
        self.assertIn("workflow_dispatch:", self.release)
        self.assertIn("version:", self.release)
        self.assertIn('"refs/heads/main"', self.release)

    def test_privileged_workflows_authorize_the_triggering_actor(self) -> None:
        for name, workflow in (
            ("release.yml", self.release),
            ("nightly.yml", self.nightly),
            ("manual_build.yml", self.manual_build),
        ):
            with self.subTest(workflow=name):
                self.assertIn("github.triggering_actor", workflow)
                self.assertIn("collaborators/${ACTOR}/permission", workflow)

    def test_scripts_run_from_the_checkout_not_a_materialized_revision(self) -> None:
        self.assertIn("python3 .github/scripts/stamp_version.py", self.build_reusable)
        self.assertIn("python3 .github/scripts/merge_appcast_channel.py", self.release)
        self.assertNotIn("TRUSTED_WORKFLOW_SHA", self.release)
        self.assertNotIn("TRUSTED_WORKFLOW_SHA", self.build_reusable)
        self.assertNotIn("RUNNER_TEMP/trusted-workflow-tools", self.release)

    def test_release_pipeline_uses_draft_based_resume_without_durable_provenance(self) -> None:
        for marker in ("release_state", "resume=", "--draft"):
            self.assertIn(marker, self.release)
        for removed in (
            "release_provenance.py",
            "boringNotch-release-provenance.json",
            "boringNotch-release-intent.json",
            "resume_state=",
        ):
            self.assertNotIn(removed, self.release)

    def test_generate_appcast_build_is_shared_not_duplicated(self) -> None:
        for name, workflow in (
            ("release.yml", self.release),
            ("nightly.yml", self.nightly),
        ):
            with self.subTest(workflow=name):
                self.assertIn("uses: ./.github/actions/build-generate-appcast", workflow)
                self.assertNotIn("Build Sparkle generate_appcast from source\n        run:", workflow)

    def test_build_numbers_come_from_the_shared_counter(self) -> None:
        counter_path = REPOSITORY_ROOT / ".github" / "build-number"
        self.assertTrue(counter_path.is_file(), ".github/build-number must exist")
        self.assertRegex(counter_path.read_text(encoding="utf-8").strip(), r"^[0-9]+$")
        for name, workflow in (
            ("release.yml", self.release),
            ("nightly.yml", self.nightly),
        ):
            with self.subTest(workflow=name):
                self.assertIn(".github/build-number", workflow)
                self.assertIn("git add", workflow)
                self.assertIn("git commit", workflow)


if __name__ == "__main__":
    unittest.main()