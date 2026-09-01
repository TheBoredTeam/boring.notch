#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RELEASE_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release.yml"
NIGHTLY_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "nightly.yml"


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.release = RELEASE_WORKFLOW.read_text(encoding="utf-8")
        cls.nightly = NIGHTLY_WORKFLOW.read_text(encoding="utf-8")

    def test_release_is_admin_dispatched_with_a_version(self) -> None:
        self.assertIn("workflow_dispatch:", self.release)
        self.assertIn("version:", self.release)
        self.assertNotIn("inputs.pr_number", self.release)
        self.assertIn('ACTOR: ${{ github.triggering_actor }}', self.release)
        self.assertIn('VERSION_INPUT: ${{ inputs.version }}', self.release)
        self.assertIn('WORKFLOW_REF: ${{ github.ref }}', self.release)
        self.assertIn('"refs/heads/main"', self.release)
        self.assertIn("Expected exactly one open same-repository dev-to-main release PR", self.release)
        self.assertNotIn("issue_comment:", self.release)
        self.assertNotIn("github.event.issue", self.release)
        self.assertNotIn("github.event.comment", self.release)

    def test_preparation_validates_the_release_once(self) -> None:
        self.assertNotIn("\n  authorize:", self.release)
        self.assertNotIn("Revalidate release PR state", self.release)
        self.assertIn("head_sha: .head.sha", self.release)
        self.assertIn("base_sha: .base.sha", self.release)
        self.assertIn('ref: ${{ steps.authorize.outputs.base_sha }}', self.release)
        self.assertIn(
            "source_sha: ${{ steps.sync_branch.outputs.source_sha || steps.authorize.outputs.head_sha }}",
            self.release,
        )
        self.assertLess(
            self.release.index('ref: ${{ steps.authorize.outputs.base_sha }}'),
            self.release.index('VERSION_INPUT: ${{ inputs.version }}'),
        )

    def test_beta_appcast_retry_is_one_idempotent_step(self) -> None:
        self.assertEqual(self.release.count("name: Publish beta appcast"), 1)
        self.assertNotIn("Merge published beta appcast (attempt", self.release)
        self.assertNotIn("Push published beta appcast (attempt", self.release)
        self.assertIn("for attempt in 1 2 3 4 5; do", self.release)

    def test_stable_appcast_does_not_expand_an_empty_array_with_nounset(self) -> None:
        self.assertNotIn('"${CHANNEL_ARGS[@]}"', self.release)
        self.assertIn("APPCAST_ARGS=(", self.release)
        self.assertIn('APPCAST_ARGS+=(--channel "${{ env.BETA_CHANNEL_NAME }}")', self.release)
        self.assertIn('"${APPCAST_ARGS[@]}"', self.release)

    def test_nightly_schedule_remains_independent(self) -> None:
        self.assertIn("schedule:", self.nightly)
        self.assertIn('NIGHTLY_BRANCH: dev', self.nightly)

if __name__ == "__main__":
    unittest.main()
