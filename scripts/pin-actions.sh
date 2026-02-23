#!/usr/bin/env bash
# scripts/pin-actions.sh
#
# Helper script to pin GitHub Actions references to immutable commit SHAs.
# Resolves each "uses: owner/repo@tag" entry in workflow files and prints the
# replacement line with the full SHA, so you can update the files manually or
# pipe the output into sed.
#
# Prerequisites:
#   - gh CLI (https://cli.github.com/) authenticated with read access.
#   - jq (https://stedolan.github.io/jq/) – pre-installed on GitHub-hosted runners.
#
# Usage:
#   ./scripts/pin-actions.sh                     # scan .github/workflows/
#   ./scripts/pin-actions.sh path/to/workflow.yml

set -euo pipefail

WORKFLOW_DIR="${1:-.github/workflows}"

echo "Scanning: $WORKFLOW_DIR"
echo ""

# Collect all unique "uses:" references
mapfile -t REFS < <(
  grep -rh 'uses: ' "$WORKFLOW_DIR" \
  | grep -oP '(?<=uses: )[^\s#]+' \
  | sort -u
)

for ref in "${REFS[@]}"; do
  owner_repo="${ref%%@*}"
  tag="${ref##*@}"
  owner="${owner_repo%%/*}"
  repo="${owner_repo##*/}"

  # Skip actions that are already pinned to a full SHA (40 hex chars)
  if [[ "$tag" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ALREADY PINNED  $ref"
    continue
  fi

  # Resolve the tag ref via the GitHub API
  api_response=$(gh api "repos/$owner/$repo/git/ref/tags/$tag" 2>/dev/null || true)
  if [[ -z "$api_response" ]]; then
    echo "UNRESOLVABLE    $ref  (tag not found or no access)"
    continue
  fi

  sha=$(echo "$api_response" | jq -r '.object.sha' 2>/dev/null || echo "")
  obj_type=$(echo "$api_response" | jq -r '.object.type' 2>/dev/null || echo "")

  # Dereference annotated tags (tag object → commit object)
  if [[ "$obj_type" == "tag" ]]; then
    tag_response=$(gh api "repos/$owner/$repo/git/tags/$sha" 2>/dev/null || true)
    sha=$(echo "$tag_response" | jq -r '.object.sha' 2>/dev/null || echo "$sha")
  fi

  if [[ -z "$sha" || "$sha" == "null" ]]; then
    echo "UNRESOLVABLE    $ref  (could not determine SHA)"
    continue
  fi

  echo "PIN  $ref"
  echo "  -> uses: $owner_repo@$sha  # $tag"
  echo ""
done
