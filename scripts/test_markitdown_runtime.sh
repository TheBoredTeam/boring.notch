#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
runtime="$project_root/boringNotch/vendor/markitdown-runtime/markitdown-local"
runtime_notices="$project_root/boringNotch/vendor/markitdown-runtime/THIRD_PARTY_LICENSES"
if [[ -n "${PYTHON_COMMAND:-}" ]]; then
    python_command="$PYTHON_COMMAND"
elif command -v brew >/dev/null 2>&1; then
    python_command="$(brew --prefix python@3.13)/bin/python3.13"
else
    python_command="${commands[python3.13]:-python3.13}"
fi

if [[ ! -x "$runtime" ]]; then
    print -u2 "Missing local runtime. Run scripts/build_markitdown_runtime.sh first."
    exit 1
fi

if [[ ! -f "$runtime_notices" ]]; then
    print -u2 "The generated runtime is missing its third-party notices."
    exit 1
fi

"$python_command" -m unittest "$project_root/tests/test_markitdown_local.py"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-markitdown-tests.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT
"$python_command" "$project_root/tests/create_markitdown_fixtures.py" "$fixture_root"

pdf_source="$fixture_root/local-test.pdf"
docx_source="$fixture_root/local-test.docx"
pdf_output="$fixture_root/local-test-pdf.md"
docx_output="$fixture_root/local-test-docx.md"

pdf_before=$(shasum -a 256 "$pdf_source" | awk '{print $1}')
docx_before=$(shasum -a 256 "$docx_source" | awk '{print $1}')

"$runtime" --input "$pdf_source" --output "$pdf_output"
"$runtime" --input "$docx_source" --output "$docx_output"

rg -q "Boring Notch PDF local conversion fixture" "$pdf_output"
rg -q "Boring Notch DOCX local conversion fixture" "$docx_output"

[[ "$pdf_before" == "$(shasum -a 256 "$pdf_source" | awk '{print $1}')" ]]
[[ "$docx_before" == "$(shasum -a 256 "$docx_source" | awk '{print $1}')" ]]
[[ "$pdf_source" != "$pdf_output" && "$docx_source" != "$docx_output" ]]

if "$runtime" --input "https://example.com/document.pdf" --output "$fixture_root/remote.md" 2>/dev/null; then
    print -u2 "The helper unexpectedly accepted a remote URL."
    exit 1
fi

rg -q "Microsoft MarkItDown MIT license" "$runtime_notices"
rg -q "Copyright \(c\) Microsoft Corporation\." "$runtime_notices"

print "PDF conversion: passed"
print "DOCX conversion: passed"
print "Source preservation: passed"
print "Local-only guard: passed"
print "Runtime license notices: passed"
