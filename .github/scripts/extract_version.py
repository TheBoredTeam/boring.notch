#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import semver
import subprocess
import sys
from argparse import ArgumentParser


SEMVER_RE = re.compile(r"v?[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


def find_first_valid(text: str):
    for cand in SEMVER_RE.findall(text or ""):
        s = cand.lstrip("v")
        try:
            parsed = semver.VersionInfo.parse(s)
            return s, parsed
        except Exception:
            continue
    return None, None


def write_github_output(version: str | None, is_beta_flag: bool) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if not out:
        return
    try:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"version={version or ''}\n")
            f.write(f"is_beta={str(is_beta_flag).lower()}\n")
    except Exception:
        pass


def main(argv=None) -> int:
    p = ArgumentParser()
    p.add_argument("-c", "--comment", help="Comment body to scan (defaults: $COMMENT or stdin)")
    args = p.parse_args(argv)

    comment = args.comment or os.environ.get("COMMENT")
    if not comment:
        comment = sys.stdin.read() or ""

    version, parsed = find_first_valid(comment)

    beta = getattr(parsed, "prerelease", None)

    # Write GitHub Actions outputs if available (GITHUB_OUTPUT)
    write_github_output(version, bool(beta))

    # For CLI consumption print simple key=value lines (and a human line)
    print(f"version={version or ''}")
    print(f"is_beta={str(bool(beta)).lower()}")
    print(f"Found version: {version} (beta: {bool(beta)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
