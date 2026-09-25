#!/usr/bin/env python3
"""Structural smoke tests for the nightly release pipeline.

The workflows cannot execute under unit test; these checks pin the nightly
rolling-release invariants (fixed tag/asset/title, attestation, signed API
commits) and the shared derive-don't-reserve build-number scheme that
stable/beta follow too.
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

    def test_nightly_uses_the_fixed_rolling_tag_and_asset(self) -> None:
        self.assertIn("TAG: nightly", self.nightly)
        self.assertIn("ASSET_NAME: boringNotch-nightly.dmg", self.nightly)
        self.assertNotRegex(self.nightly, r'TAG="nightly-\$')
        self.assertNotRegex(self.nightly, r"ASSET_NAME=\"boringNotch-\$")

    def test_nightly_uses_the_rolling_release_title(self) -> None:
        self.assertIn("TITLE: Latest Nightly", self.nightly)
        self.assertNotIn("Nightly ${BRANCH_NAME}\n", self.nightly.replace("Nightly ${BRANCH_NAME}</h2>", ""))

    def test_nightly_appcast_targets_the_fixed_release_url(self) -> None:
        self.assertIn("appcast-dev.xml", self.nightly)
        # TAG is pinned to `nightly` below, so this prefix always resolves to
        # .../releases/download/nightly/.
        self.assertIn(
            "https://github.com/TheBoredTeam/boring.notch/releases/download/${TAG}/",
            self.nightly,
        )
        self.assertIn("TAG: nightly", self.nightly)
        self.assertNotIn("download/${ASSET_NAME}", self.nightly)

    def test_nightly_attests_the_final_dmg_with_a_pinned_action(self) -> None:
        self.assertIn("uses: actions/attest@", self.nightly)
        attest_line = next(
            line for line in self.nightly.splitlines() if "uses: actions/attest@" in line
        )
        sha = attest_line.split("actions/attest@")[1].split()[0]
        self.assertRegex(sha, r"^[0-9a-f]{40}$")
        self.assertIn("subject-path: Release/${{ env.ASSET_NAME }}", self.nightly)
        for permission in ("id-token: write", "attestations: write", "artifact-metadata: write"):
            self.assertIn(permission, self.nightly)

    def test_nightly_uploads_the_fixed_asset_with_clobber(self) -> None:
        self.assertIn("--clobber", self.nightly)

    def test_nightly_publishes_a_single_rolling_release(self) -> None:
        # The release is created once as a draft and only published after the
        # asset upload; existing releases are reused, never recreated.
        self.assertIn("gh release create \"${TAG}\"", self.nightly)
        self.assertIn("gh release upload \"${TAG}\" \"Release/${ASSET_NAME}\" --clobber", self.nightly)
        self.assertIn("gh release edit \"${TAG}\" --draft=false", self.nightly)
        self.assertIn("--target \"${SOURCE_SHA}\"", self.nightly)

    def test_nightly_moves_the_tag_instead_of_creating_unique_tags(self) -> None:
        self.assertIn("git/ref/tags/${TAG}", self.nightly)
        self.assertIn('{"sha":"%s","force":true}', self.nightly)
        self.assertIn('-X PATCH "repos/${REPO}/git/refs/tags/${TAG}"', self.nightly)
        self.assertIn('-X POST "repos/${REPO}/git/refs"', self.nightly)

    def test_nightly_commits_go_through_the_signed_git_database_api(self) -> None:
        self.assertNotIn("git config user.name", self.nightly)
        self.assertNotIn("git commit -m", self.nightly)
        self.assertNotIn("git push", self.nightly)
        for endpoint in ("git/trees", "git/commits", "git/refs/heads/"):
            self.assertIn(endpoint, self.nightly)
        # No custom author/committer may be supplied: omitting them is what
        # makes GitHub sign the commit as the bot identity.
        self.assertNotIn('"author"', self.nightly)
        self.assertNotIn('"committer"', self.nightly)

    def test_nightly_signed_commits_use_the_trees_then_commits_flow(self) -> None:
        # POST git/commits takes `tree` as a single SHA string; entries go
        # through POST git/trees first. The one remaining commit site (the
        # appcast) must follow that two-request flow (verified against the
        # live API); the build-number reservation commit no longer exists.
        self.assertEqual(self.nightly.count('gh api -X POST "repos/${REPO}/git/trees"'), 1)
        self.assertEqual(self.nightly.count('gh api -X POST "repos/${REPO}/git/commits"'), 1)
        self.assertEqual(self.nightly.count("--arg tree"), 2)
        # base_tree is documented as a tree object SHA; the workflow must
        # resolve the head commit's tree rather than pass a commit SHA and
        # rely on undocumented API tolerance.
        self.assertEqual(self.nightly.count("base_tree: $tree"), 1)
        # Line-exact: "base_tree: $tree" also contains "tree: $tree".
        commit_tree_lines = [
            line for line in self.nightly.splitlines() if line.strip() == "tree: $tree,"
        ]
        self.assertEqual(len(commit_tree_lines), 1)
        self.assertEqual(self.nightly.count(".tree.sha"), 1)
        self.assertNotIn(".commit.tree.sha", self.nightly)

    def test_nightly_ref_updates_are_verified_and_non_force_for_branches(self) -> None:
        self.assertEqual(self.nightly.count('jq -r \'.verification.verified\''), 1)
        self.assertEqual(self.nightly.count('is not verified'), 1)
        self.assertIn('{"sha":"%s","force":false}', self.nightly)
        # The only force update is the intentionally mutable rolling tag.
        self.assertEqual(self.nightly.count('"force":true'), 1)

    def test_nightly_appcast_commit_rebases_onto_the_current_dev_head(self) -> None:
        # dev may advance during the build as long as it still contains the
        # built source commit; the appcast commit parents onto the live head.
        self.assertIn("repos/${REPO}/compare/${SOURCE_SHA}...${CURRENT_HEAD}", self.nightly)
        self.assertIn("no longer contains the built source", self.nightly)
        # compare is base...head: base=built source, head=live dev, so the
        # acceptable relations are ahead/identical, never behind.
        self.assertIn('[[ "$RELATION" == "ahead" || "$RELATION" == "identical" ]]', self.nightly)
        self.assertNotIn('"$RELATION" == "behind"', self.nightly)

    def test_nightly_generates_from_a_single_clean_appcast_input(self) -> None:
        self.assertIn("Prepare single nightly appcast input", self.nightly)
        self.assertIn("rm -rf \"$APPCAST_INPUT\"", self.nightly)
        self.assertIn("cp \"Release/${ASSET_NAME}\" \"$APPCAST_INPUT/\"", self.nightly)
        self.assertIn("cp \"Release/${ASSET_NAME%.dmg}.html\" \"$APPCAST_INPUT/\"", self.nightly)
        self.assertIn('APPCAST_OUTPUT: ${{ runner.temp }}/${{ env.APPCAST_FILE }}', self.nightly)
        self.assertIn('mv "$APPCAST_OUTPUT" "updater/${APPCAST_FILE}"', self.nightly)
        self.assertNotIn("prune_appcast_channel.py", self.nightly)

    def test_generate_appcast_comes_from_the_official_release_tarball(self) -> None:
        action = (
            REPOSITORY_ROOT / ".github" / "actions" / "fetch-generate-appcast" / "action.yml"
        ).read_text(encoding="utf-8")
        # Both pipelines use the shared fetch action.
        for name, workflow in (("nightly.yml", self.nightly), ("release.yml", self.release)):
            with self.subTest(workflow=name):
                self.assertIn("uses: ./.github/actions/fetch-generate-appcast", workflow)
                self.assertNotIn("build-generate-appcast", workflow)
        # The tool is downloaded from the official release asset, never compiled.
        self.assertIn("releases/download/$SPARKLE_TAG/Sparkle-$SPARKLE_TAG.tar.xz", action)
        self.assertIn("bin/generate_appcast", action)
        self.assertNotIn("xcodebuild", action)
        # The tag must resolve to the exact revision pinned in Package.resolved.
        self.assertIn("Package.resolved", action)
        self.assertIn("resolves to ${TAG_SHA}, expected ${SPARKLE_REVISION}", action)

    def test_nightly_builds_the_live_branch_head(self) -> None:
        # Nightlies ship real commits: the pipeline must never create
        # reservation commits on dev before building. The head is read twice
        # (prepare and the appcast rebase); the only branch ref PATCH is the
        # appcast commit landing on top of the live head.
        self.assertNotIn("Reserve build number", self.nightly)
        self.assertEqual(
            self.nightly.count("git/ref/heads/${BRANCH_NAME}\" --jq '.object.sha'"), 2
        )
        self.assertEqual(
            self.nightly.count('-X PATCH "repos/${REPO}/git/refs/heads/${BRANCH_NAME}"'), 1
        )
        self.assertIn("short_sha=${SOURCE_SHA::7}", self.nightly)

    def test_nightly_build_number_is_derived_not_reserved(self) -> None:
        # The counter file and its signed reservation commit are gone: the
        # build number is one above the highest released sparkle:version across
        # every channel, floored by the number committed in the Xcode project.
        self.assertNotIn(".github/build-number", self.nightly)
        self.assertNotIn("group: release-build-number", self.nightly)
        self.assertIn("sparkle:version", self.nightly)
        # The dev appcast is read from the source being built; stable/beta is
        # read from live main so a beta published after the source snapshot is
        # still part of the ceiling.
        self.assertIn(
            'APPCAST_SOURCES="updater/${APPCAST_FILE}@${SOURCE_SHA} updater/appcast.xml@main"',
            self.nightly,
        )
        self.assertIn("for APPCAST_SOURCE in ${APPCAST_SOURCES}", self.nightly)
        self.assertIn('APPCAST="${APPCAST_SOURCE%@*}"', self.nightly)
        self.assertIn('APPCAST_REF="${APPCAST_SOURCE##*@}"', self.nightly)
        self.assertIn('?ref=${APPCAST_REF}"', self.nightly)
        # Both Sparkle serializations: generate_appcast writes the element
        # form (<sparkle:version>274</sparkle:version>); accept the attribute
        # form too so hand-edited appcasts still count.
        self.assertIn(
            "grep -Eo 'sparkle:version(=\"|>)[0-9]+'", self.nightly
        )
        self.assertIn("CURRENT_PROJECT_VERSION", self.nightly)
        self.assertIn(
            'BUILD_NUMBER="$(( RELEASED > BASE_BUILD ? RELEASED + 1 : BASE_BUILD + 1 ))"',
            self.nightly,
        )
        # The derived number is still re-emitted for the reusable build job.
        self.assertIn('echo "build_number=$BUILD_NUMBER"', self.nightly)
        self.assertIn("build_number: ${{ needs.prepare.outputs.build_number }}", self.nightly)

    def test_stable_and_beta_derive_build_numbers_like_nightly(self) -> None:
        # release.yml shares the nightly derivation: one above the highest
        # sparkle:version already published through Sparkle, floored by the
        # number committed in the Xcode project. The counter file and its
        # reservation commit on dev are gone, so releases ship the reviewed
        # PR head instead of a bump commit.
        self.assertNotIn(".github/build-number", self.release)
        self.assertNotIn("Reserve build number", self.release)
        self.assertNotIn("reserve_build_number", self.release)
        self.assertIn("Derive build number", self.release)
        # Same Sparkle serializations as the nightly derivation.
        self.assertIn('grep -Eo \'sparkle:version(="|>)[0-9]+\'', self.release)
        self.assertIn("CURRENT_PROJECT_VERSION", self.release)
        # Identical cross-channel ceiling: max sparkle:version across the dev
        # appcast at the built source and the stable/beta appcast at live main.
        self.assertIn(
            'APPCAST_SOURCES="updater/appcast-dev.xml@${SOURCE_SHA} updater/appcast.xml@main"',
            self.release,
        )
        self.assertIn("for APPCAST_SOURCE in ${APPCAST_SOURCES}", self.release)
        self.assertIn('APPCAST="${APPCAST_SOURCE%@*}"', self.release)
        self.assertIn('APPCAST_REF="${APPCAST_SOURCE##*@}"', self.release)
        self.assertIn('?ref=${APPCAST_REF}"', self.release)
        # The derivation runs only for fresh releases; resume runs publish an
        # already-stamped draft and must not re-derive a build number.
        derive_block = self.release.split("Derive build number", 1)[1].split("- name:", 1)[0]
        self.assertIn("steps.release_state.outputs.resume == 'false'", derive_block)
        # Identical derivation expression in both pipelines.
        for workflow in (self.release, self.nightly):
            self.assertIn(
                'BUILD_NUMBER="$(( RELEASED > BASE_BUILD ? RELEASED + 1 : BASE_BUILD + 1 ))"',
                workflow,
            )
        self.assertIn('echo "build_number=$BUILD_NUMBER"', self.release)
        self.assertIn("build_number: ${{ needs.preparation.outputs.build_number }}", self.release)

    def test_build_number_uses_live_main_beta_and_cannot_reuse_its_build(self) -> None:
        # Regression for the nightly/beta collision: the source snapshot has
        # nightly 277, while main has already published beta 278.
        source_appcast_builds = [277]
        main_appcast_builds = [271, 278]
        project_build = 271
        released = max(source_appcast_builds + main_appcast_builds)
        build_number = (
            released + 1 if released > project_build else project_build + 1
        )

        self.assertEqual(released, 278)
        self.assertEqual(build_number, 279)
        for workflow in (self.nightly, self.release):
            with self.subTest(workflow="branch-aware appcasts"):
                self.assertIn("@${SOURCE_SHA} updater/appcast.xml@main", workflow)
                self.assertIn("?ref=${APPCAST_REF}", workflow)
                self.assertIn("BUILD_NUMBER=\"$(( RELEASED > BASE_BUILD ?", workflow)

    def test_nightly_gates_manual_runs_with_the_shared_admin_action(self) -> None:
        action = (
            REPOSITORY_ROOT / ".github" / "actions" / "require-admin" / "action.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("collaborators/", action)
        self.assertIn('"admin"', action)
        self.assertIn("workflow_dispatch", action)
        # Both API-mutating jobs gate manual runs and reruns via the action.
        self.assertEqual(self.nightly.count("uses: ./.github/actions/require-admin"), 2)

    def test_nightly_does_not_delete_any_releases(self) -> None:
        # Legacy nightly-* cleanup is handled outside the pipeline by design;
        # the nightly workflow must never destroy release or tag data.
        self.assertNotIn('-X DELETE "repos/${REPO}/releases/', self.nightly)
        self.assertNotIn("gh release delete", self.nightly)

    def test_nightly_release_notes_carry_a_caution_warning(self) -> None:
        # The rolling release description must warn about nightly-build risks,
        # appended as its own line after the build info.
        self.assertIn("CAUTION_WARNING", self.nightly)
        nightly_lower = self.nightly.lower()
        self.assertIn("automated build", nightly_lower)
        self.assertIn("use at your own risk", nightly_lower)
        self.assertIn("${CAUTION_WARNING}", self.nightly)

    def test_nightly_embedded_notes_do_not_leak_the_commit_message(self) -> None:
        # Nightly notes intentionally carry only the commit SHA and source
        # link; the raw commit message was dropped as noisy release notes.
        self.assertNotIn("commit_message", self.nightly)
        self.assertNotIn("COMMIT_MESSAGE", self.nightly)
        self.assertNotIn("<p>Message:", self.nightly)
        # Notes are still embedded in the appcast for the update dialog.
        self.assertIn("Create embedded release notes", self.nightly)
        self.assertIn("--embed-release-notes", self.nightly)

    def test_nightly_configures_a_dedicated_dev_channel(self) -> None:
        # The app-channel implementation is maintained separately from this
        # workflow change; pin the pipeline-side channel contract here.
        self.assertIn("appcast-dev.xml", self.nightly)
        self.assertIn('--channel "${BRANCH_NAME}"', self.nightly)
        self.assertIn("Prepare single nightly appcast input", self.nightly)

    def test_nightly_keeps_sparkle_channel_and_embedded_notes_and_key(self) -> None:
        self.assertIn("--channel \"${BRANCH_NAME}\"", self.nightly)
        self.assertIn("--embed-release-notes", self.nightly)
        self.assertIn("PRIVATE_SPARKLE_KEY", self.nightly)

    def test_immutable_release_checks_are_absent_from_nightly(self) -> None:
        for removed in ("immutable", ".immutable", "immutable-release"):
            self.assertNotIn(removed, self.nightly)

    def test_built_product_is_named_boring_notch(self) -> None:
        # The Xcode product name is "Boring Notch" (so the built app, DMG, and
        # artifact names carry the space), while the project/target/scheme stay
        # boringNotch. Every pipeline that ships the built product must address
        # it through APP_NAME, never PROJECT_NAME.
        pbxproj = (
            REPOSITORY_ROOT / "boringNotch.xcodeproj" / "project.pbxproj"
        ).read_text(encoding="utf-8")
        self.assertEqual(pbxproj.count('PRODUCT_NAME = "Boring Notch";'), 2)
        self.assertEqual(pbxproj.count('PRODUCT_MODULE_NAME = boringNotch;'), 2)
        self.assertEqual(pbxproj.count('INFOPLIST_KEY_CFBundleName = "Boring Notch";'), 2)
        self.assertEqual(pbxproj.count('INFOPLIST_KEY_CFBundleDisplayName = "Boring Notch";'), 2)
        self.assertEqual(
            pbxproj.count(
                'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Boring Notch.app/'
                '$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Boring Notch";'
            ),
            2,
        )

        scheme = (
            REPOSITORY_ROOT
            / "boringNotch.xcodeproj"
            / "xcshareddata"
            / "xcschemes"
            / "boringNotch.xcscheme"
        ).read_text(encoding="utf-8")
        self.assertEqual(scheme.count('BuildableName = "Boring Notch.app"'), 3)
        self.assertIn("<TestAction", scheme)
        self.assertIn('BlueprintName = "boringNotchTests"', scheme)

        # Reusable build: archives under the project name, exports/ships the
        # app and DMG under APP_NAME.
        self.assertIn("APP_NAME: Boring Notch", self.build_reusable)
        self.assertIn('"Release/$APP_NAME.app"', self.build_reusable)
        self.assertIn('"Release/$APP_NAME.dmg"', self.build_reusable)
        self.assertIn('name: ${{ env.APP_NAME }}.dmg', self.build_reusable)
        self.assertNotIn("Release/$PROJECT_NAME.app", self.build_reusable)
        self.assertNotIn("Release/$PROJECT_NAME.dmg", self.build_reusable)

        # Release pipeline: draft download, artifact download, release upload,
        # and the Homebrew cask all point at the renamed product.
        self.assertIn("APP_NAME: Boring Notch", self.release)
        self.assertIn('--pattern "$APP_NAME.dmg"', self.release)
        self.assertIn('name: ${{ env.APP_NAME }}.dmg', self.release)
        self.assertIn('"Release/$APP_NAME.dmg"', self.release)
        self.assertIn("/Boring%20Notch.dmg", self.release)
        self.assertIn('app "Boring Notch.app"', self.release)
        self.assertNotIn("boringNotch.dmg", self.release)
        self.assertNotIn('app "boringNotch.app"', self.release)

        readme = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("releases/latest/download/Boring%20Notch.dmg", readme)
        self.assertNotIn("releases/latest/download/boringNotch.dmg", readme)

        # Nightly: downloads the renamed artifact, then renames to the fixed
        # rolling asset name (which is intentionally unchanged).
        self.assertIn("APP_NAME: Boring Notch", self.nightly)
        self.assertIn('name: ${{ env.APP_NAME }}.dmg', self.nightly)
        self.assertIn('mv "Release/${APP_NAME}.dmg" "Release/${ASSET_NAME}"', self.nightly)
        self.assertNotIn("${PROJECT_NAME}.dmg", self.nightly)

    def test_stable_and_beta_workflows_are_unchanged(self) -> None:
        # Stable/beta live in release.yml; pin the load-bearing invariants the
        # nightly changes must not disturb.
        self.assertIn("APPCAST_OUT=\"appcast-beta.xml\"", self.release)
        self.assertIn("APPCAST_OUT=\"appcast-stable.xml\"", self.release)
        self.assertIn("merge_appcast_channel.py", self.release)
        self.assertIn("updater/appcast.xml", self.release)
        self.assertIn("publish_stable", self.release)
        self.assertIn("publish_beta", self.release)
        self.assertNotIn("boringNotch-nightly.dmg", self.release)
        self.assertNotIn('TAG: nightly', self.release)
        self.assertNotIn("actions/attest", self.release)
        self.assertNotIn("artifact-metadata", self.release)
        self.assertNotIn('startswith("nightly-")', self.release)

    def test_release_never_probes_releases_by_tag_for_draft_state(self) -> None:
        # The /releases/tags REST endpoint 404s for draft releases even with
        # write access, so release-state decisions must never call it.
        # (Comments may mention the endpoint; call sites may not.)
        # gh release view resolves drafts via the list API instead.
        self.assertNotRegex(self.release, r'gh api "repos/[^"]*/releases/tags')
        # Five call sites: resume probe, two notes reads, stable publish, beta publish.
        self.assertEqual(self.release.count('gh release view "'), 5)
        stable_block = self.release.split("  publish_stable:", 1)[1].split("  publish_beta:", 1)[0]
        beta_block = self.release.split("  publish_beta:", 1)[1].split("  upgrade-brew:", 1)[0]
        for job, block in (("publish_stable", stable_block), ("publish_beta", beta_block)):
            self.assertIn('gh release view "$TAG"', block, job)
            self.assertIn("--json isDraft", block, job)
            self.assertIn("is already published", block, job)
            self.assertIn("does not exist; expected the draft", block, job)

    def test_release_resume_reads_the_draft_target_commitish(self) -> None:
        # Resuming from a draft must recover its source commit; the
        # list-backed gh release view exposes it as targetCommitish.
        self.assertIn('gh release view "$TAG" --repo "$REPO" --json isDraft,targetCommitish', self.release)
        self.assertIn("jq -r '.isDraft'", self.release)
        self.assertIn("jq -r '.targetCommitish'", self.release)
        self.assertIn('grep -q \'release not found\'', self.release)

    def test_release_resume_notes_come_from_the_draft_release(self) -> None:
        # Resume regenerates release notes from the existing draft; probing
        # it must work while the release is still a draft.
        resume_block = self.release.split("Generate release notes", 1)[1].split("- name:", 1)[0]
        self.assertIn('gh release view "v${VERSION}" --repo "$REPO" --json name', resume_block)
        self.assertIn('gh release view "v${VERSION}" --repo "$REPO" --json body', resume_block)


if __name__ == "__main__":
    unittest.main()
