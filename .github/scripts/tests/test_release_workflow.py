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

    def test_release_is_admin_dispatched_with_explicit_inputs(self) -> None:
        self.assertIn("workflow_dispatch:", self.release)
        self.assertIn("pr_number:", self.release)
        self.assertIn("version:", self.release)
        self.assertIn('PR_NUMBER: ${{ inputs.pr_number }}', self.release)
        self.assertIn('ACTOR: ${{ github.triggering_actor }}', self.release)
        self.assertIn('VERSION_INPUT: ${{ inputs.version }}', self.release)
        self.assertIn('WORKFLOW_REF: ${{ github.ref }}', self.release)
        self.assertIn('"refs/heads/main"', self.release)
        self.assertIn('if [[ ! "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]]; then', self.release)

    def test_release_does_not_consume_issue_comment_data(self) -> None:
        self.assertNotIn("issue_comment:", self.release)
        self.assertNotIn("github.event.issue", self.release)
        self.assertNotIn("github.event.comment", self.release)

    def test_release_derives_source_from_the_validated_pr(self) -> None:
        self.assertIn("head_sha: .head.sha", self.release)
        self.assertIn("base_sha: .base.sha", self.release)
        self.assertIn('ref: ${{ needs.authorize.outputs.base_sha }}', self.release)
        self.assertIn(
            "source_sha: ${{ steps.sync_branch.outputs.source_sha || needs.authorize.outputs.head_sha }}",
            self.release,
        )
        self.assertLess(
            self.release.index('ref: ${{ needs.authorize.outputs.base_sha }}'),
            self.release.index('VERSION_INPUT: ${{ inputs.version }}'),
        )

    def test_nightly_schedule_remains_independent(self) -> None:
        self.assertIn("schedule:", self.nightly)
        self.assertIn('NIGHTLY_BRANCH: dev', self.nightly)


if __name__ == "__main__":
    unittest.main()
