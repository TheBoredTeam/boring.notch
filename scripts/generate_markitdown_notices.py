#!/usr/bin/env python3
"""Generate complete notices for the pinned MarkItDown helper runtime."""

from __future__ import annotations

import argparse
import re
from importlib.metadata import PackageNotFoundError, distribution
from pathlib import Path


MIT_TERMS = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""

BSD_THREE_CLAUSE = """Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."""


def normalize(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def locked_names(requirements: Path) -> list[str]:
    names: list[str] = []
    for raw_line in requirements.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        names.append(line.split("==", 1)[0])
    return sorted(names, key=normalize)


def license_files(package_name: str) -> list[tuple[str, str]]:
    dist = distribution(package_name)
    found: list[tuple[str, str]] = []
    for entry in dist.files or []:
        path_text = str(entry)
        basename = Path(path_text).name.lower()
        parent_parts = [part.lower() for part in Path(path_text).parts]
        is_notice_name = basename.startswith(
            ("license", "copying", "notice", "copyright", "authors")
        )
        is_license_directory = "licenses" in parent_parts and Path(path_text).suffix.lower() in {
            "", ".txt", ".md", ".rst", ".html",
        }
        if not (is_notice_name or is_license_directory):
            continue
        located = Path(dist.locate_file(entry))
        if not located.is_file():
            continue
        try:
            text = located.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = located.read_text(encoding="latin-1")
        found.append((path_text, text.strip()))
    return sorted(found)


def apache_terms() -> str:
    for package_name in ("cryptography", "packaging"):
        for path, text in license_files(package_name):
            if path.lower().endswith(("license.apache", "license.apache.txt")):
                return text
    raise RuntimeError("Could not locate the locked Apache-2.0 license text")


def fallback_notices(package_name: str) -> list[tuple[str, str]]:
    apache = apache_terms()
    notices = {
        "cobble": [
            (
                "declared BSD license",
                "Copyright Michael Williamson\n\n" + BSD_THREE_CLAUSE,
            )
        ],
        "et-xmlfile": [
            (
                "declared MIT license",
                "Copyright et_xmlfile contributors, including Charlie Clark, Daniel Hillier, and Elias Rabel\n\n"
                + MIT_TERMS,
            )
        ],
        "flatbuffers": [
            ("declared Apache-2.0 license", "Copyright Google LLC\n\n" + apache)
        ],
        "magika": [
            ("declared Apache-2.0 license", "Copyright Google LLC\n\n" + apache)
        ],
        "markitdown": [
            (
                "Microsoft MarkItDown MIT license",
                "Copyright (c) Microsoft Corporation.\n\n" + MIT_TERMS,
            )
        ],
        "openpyxl": [
            (
                "declared MIT license",
                "Copyright (c) 2010 openpyxl contributors\n\n" + MIT_TERMS,
            )
        ],
    }
    return notices.get(normalize(package_name), [])


def project_url(metadata: object) -> str:
    get_all = getattr(metadata, "get_all")
    for value in get_all("Project-URL", []) or []:
        if "," in value:
            label, url = value.split(",", 1)
            if label.strip().lower() in {"source", "repository", "homepage"}:
                return url.strip()
    get = getattr(metadata, "get")
    return get("Home-page", "") or ""


def generate(requirements: Path, python_license: Path) -> str:
    sections = [
        "Boring Notch local MarkItDown runtime: third-party notices",
        "=" * 62,
        "",
        "This file is generated from requirements/markitdown-runtime.txt and the",
        "license files shipped in the exact installed Python distributions. The",
        "runtime is bundled with Boring Notch, which remains licensed under GPL-3.0.",
        "",
        "Python runtime",
        "--------------",
        python_license.read_text(encoding="utf-8").strip(),
    ]

    for name in locked_names(requirements):
        try:
            dist = distribution(name)
        except PackageNotFoundError as error:
            raise RuntimeError(f"Locked package is not installed: {name}") from error
        metadata = dist.metadata
        declared = metadata.get("License-Expression") or metadata.get("License") or "See notices below"
        sections.extend(
            [
                "",
                "-" * 78,
                f"{metadata.get('Name', name)} {dist.version}",
                f"Declared license: {declared}",
                f"Source: {project_url(metadata) or 'not declared in package metadata'}",
                "-" * 78,
            ]
        )
        notices = license_files(name) or fallback_notices(name)
        if not notices:
            raise RuntimeError(f"No license notice found for {name} {dist.version}")
        seen: set[str] = set()
        for path, text in notices:
            if not text or text in seen:
                continue
            seen.add(text)
            sections.extend(["", f"[{path}]", "", text])

    # Preserve every notice line while removing packaging-only end-of-line
    # whitespace so the generated artifact passes Git's whitespace checks.
    return "\n".join(
        line.rstrip() for line in "\n".join(sections).splitlines()
    ).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", required=True, type=Path)
    parser.add_argument("--python-license", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.write_text(
        generate(args.requirements, args.python_license), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
