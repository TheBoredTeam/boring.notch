#!/usr/bin/env python3
"""
Update appcast.xml with a new release item and emit the GitHub Release notes
extracted from CHANGELOG.md.

Usage:
  update_appcast.py \
    --version 1.0.0 \
    --build 42 \
    --dmg-url https://github.com/<org>/gojo/releases/download/v1.0.0/Gojo-1.0.0.dmg \
    --dmg-size 12345678 \
    --ed-signature-line 'sparkle:edSignature="..." length="..."' \
    --min-system-version 14.0 \
    --pub-date "Wed, 21 May 2026 13:00:00 +0000" \
    --changelog CHANGELOG.md \
    --release-notes-out .build/release-notes.md \
    --appcast appcast.xml
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True, help="Marketing version, e.g. 1.0.0")
    p.add_argument("--build", required=True, help="CFBundleVersion (monotonic build #)")
    p.add_argument("--dmg-url", required=True)
    p.add_argument("--dmg-size", required=True, help="Bytes")
    p.add_argument(
        "--ed-signature-line",
        required=True,
        help="Output line from `sign_update`, e.g. 'sparkle:edSignature=\"...\" length=\"...\"'",
    )
    p.add_argument("--min-system-version", default="14.0")
    p.add_argument(
        "--pub-date",
        default=None,
        help="RFC 822 date; defaults to current UTC time",
    )
    p.add_argument("--changelog", default="CHANGELOG.md")
    p.add_argument("--release-notes-out", default=".build/release-notes.md")
    p.add_argument("--appcast", default="appcast.xml")
    return p.parse_args()


def extract_changelog_section(changelog_path: Path, version: str) -> str:
    """Pull the markdown block for `## [<version>]` from CHANGELOG.md."""
    text = changelog_path.read_text()
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)",
        flags=re.MULTILINE | re.DOTALL,
    )
    m = pattern.search(text)
    if not m:
        sys.exit(
            f"Could not find a `## [{version}]` section in {changelog_path}. "
            f"Add a CHANGELOG entry for this version before releasing."
        )
    body = m.group(1)
    # Strip reference-style link definitions like `[1.0.0]: https://...`
    body = re.sub(r"^\[[^\]]+\]:\s*\S+\s*$", "", body, flags=re.MULTILINE)
    return body.strip()


def parse_signature_line(line: str) -> tuple[str, str]:
    """Pull edSignature value and length value out of sign_update's output."""
    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', line)
    len_match = re.search(r'length="([^"]+)"', line)
    if not sig_match or not len_match:
        sys.exit(f"Could not parse sign_update output: {line!r}")
    return sig_match.group(1), len_match.group(1)


def build_item_xml(args: argparse.Namespace, notes_md: str, ed_sig: str, length: str) -> str:
    pub_date = args.pub_date or datetime.datetime.now(datetime.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    # Naive markdown → HTML for the notes block. Good enough for the release-notes window.
    notes_html_lines = []
    for line in notes_md.splitlines():
        line = line.rstrip()
        if not line:
            continue
        if line.startswith("### "):
            notes_html_lines.append(f"<h4>{line[4:]}</h4>")
        elif line.startswith("## "):
            notes_html_lines.append(f"<h3>{line[3:]}</h3>")
        elif line.startswith("- "):
            notes_html_lines.append(f"<li>{line[2:]}</li>")
        else:
            notes_html_lines.append(f"<p>{line}</p>")
    # Group consecutive <li> into a <ul>
    grouped: list[str] = []
    buffer: list[str] = []
    for line in notes_html_lines:
        if line.startswith("<li>"):
            buffer.append(line)
        else:
            if buffer:
                grouped.append("<ul>" + "".join(buffer) + "</ul>")
                buffer = []
            grouped.append(line)
    if buffer:
        grouped.append("<ul>" + "".join(buffer) + "</ul>")
    notes_html = "\n".join(grouped)

    return f"""    <item>
      <title>Version {args.version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{args.min_system_version}</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes_html}
      ]]></description>
      <enclosure
        url="{args.dmg_url}"
        sparkle:edSignature="{ed_sig}"
        length="{length}"
        type="application/octet-stream" />
    </item>
"""


def insert_item(appcast_path: Path, item_xml: str) -> None:
    text = appcast_path.read_text()
    # Insert directly after the <channel> opening tag's <language> line if present,
    # otherwise after <description>.
    anchor = "<language>en</language>"
    if anchor not in text:
        anchor = re.search(r"<description>[^<]*</description>", text).group(0)
    new_text = text.replace(anchor, anchor + "\n" + item_xml, 1)
    appcast_path.write_text(new_text)


def main() -> None:
    args = parse_args()
    changelog_path = Path(args.changelog)
    appcast_path = Path(args.appcast)

    notes = extract_changelog_section(changelog_path, args.version)

    notes_out = Path(args.release_notes_out)
    notes_out.parent.mkdir(parents=True, exist_ok=True)
    notes_out.write_text(notes + "\n")

    ed_sig, length = parse_signature_line(args.ed_signature_line)
    item_xml = build_item_xml(args, notes, ed_sig, length)
    insert_item(appcast_path, item_xml)

    print(f"✓ Inserted appcast item for v{args.version}")
    print(f"✓ Wrote release notes to {notes_out}")


if __name__ == "__main__":
    main()
