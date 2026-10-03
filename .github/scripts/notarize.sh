#!/usr/bin/env bash
set -euo pipefail

# Submit a .app or .dmg to Apple's notary service, wait for the verdict and
# staple the ticket to the artifact.
# Usage: notarize.sh <path to .app or .dmg>
# Requires NOTARY_KEY_PATH (App Store Connect API key, .p8), NOTARY_API_KEY_ID
# and NOTARY_API_ISSUER_ID in the environment.

TARGET="${1:?Path to .app or .dmg required}"
: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
: "${NOTARY_API_KEY_ID:?NOTARY_API_KEY_ID is required}"
: "${NOTARY_API_ISSUER_ID:?NOTARY_API_ISSUER_ID is required}"

NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/notarize.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# The notary service accepts .dmg, .pkg and .zip; app bundles are zipped first.
SUBMIT_PATH="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT_PATH="$WORK_DIR/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT_PATH"
fi

echo "Submitting $(basename "$TARGET") for notarization..."
set +e
xcrun notarytool submit "$SUBMIT_PATH" "${NOTARY_AUTH[@]}" \
  --wait --timeout 45m --output-format json > "$WORK_DIR/submit.json"
SUBMIT_EXIT=$?
set -e

read_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' \
    "$WORK_DIR/submit.json" "$1" 2>/dev/null || true
}
SUBMISSION_ID="$(read_field id)"
STATUS="$(read_field status)"

if [[ -z "$SUBMISSION_ID" ]]; then
  cat "$WORK_DIR/submit.json" >&2 || true
  echo "::error::notarytool submit failed (exit $SUBMIT_EXIT) without returning a submission id"
  exit 1
fi

echo "Submission $SUBMISSION_ID finished with status: $STATUS"
# The log lists every rejected binary and also warnings on accepted submissions.
xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH[@]}" || true

if [[ "$STATUS" != "Accepted" ]]; then
  echo "::error::Notarization of $(basename "$TARGET") failed with status '$STATUS' (submission $SUBMISSION_ID)"
  exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
