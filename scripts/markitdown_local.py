#!/usr/bin/env python3
"""Strictly local MarkItDown command used by the Boring Notch shelf."""

from __future__ import annotations

import argparse
import mimetypes
import os
import socket
import sys
from pathlib import Path


SUPPORTED_EXTENSIONS = {
    ".pdf", ".docx", ".pptx", ".xlsx", ".xls", ".html", ".htm",
    ".csv", ".json", ".jsonl", ".xml", ".rss", ".atom", ".epub",
    ".msg", ".zip", ".txt", ".md", ".markdown", ".rst", ".log",
}


def _disable_network() -> None:
    """Deny Python socket connections even if a future dependency attempts one."""

    class LocalOnlySocket(socket.socket):
        def connect(self, *args, **kwargs):  # type: ignore[no-untyped-def]
            raise RuntimeError("Network access is disabled for local Markdown conversion")

        def connect_ex(self, *args, **kwargs):  # type: ignore[no-untyped-def]
            raise RuntimeError("Network access is disabled for local Markdown conversion")

    def denied_connection(*args, **kwargs):  # type: ignore[no-untyped-def]
        raise RuntimeError("Network access is disabled for local Markdown conversion")

    socket.socket = LocalOnlySocket
    socket.create_connection = denied_connection

    for key in (
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
    ):
        os.environ.pop(key, None)
    os.environ["NO_PROXY"] = "*"
    os.environ["no_proxy"] = "*"


def _initialize_sandbox_safe_mimetypes() -> None:
    """Avoid MIME database files outside the app sandbox container."""

    # The default Python MIME initialization reads system paths including
    # /etc/apache2/mime.types, which a sandboxed macOS app cannot access.
    # Python 3.13 prepends `knownfiles` even when `init(files=[])` is used, so
    # clear that list first. This keeps the built-in mappings and prevents all
    # external MIME database reads.
    mimetypes.knownfiles = []
    mimetypes.init(files=[])


def convert(input_path: Path, output_path: Path) -> None:
    if not input_path.is_absolute() or not output_path.is_absolute():
        raise ValueError("Input and output paths must be absolute")
    if not input_path.is_file():
        raise FileNotFoundError(f"Input file does not exist: {input_path}")
    if input_path.resolve() == output_path.resolve():
        raise ValueError("Input and output paths must be different")
    if input_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported local file type: {input_path.suffix or '(none)'}")

    _disable_network()
    _initialize_sandbox_safe_mimetypes()

    from markitdown import MarkItDown

    converter = MarkItDown(enable_plugins=False)
    result = converter.convert_local(input_path)
    markdown = result.markdown
    if not markdown or not markdown.strip():
        raise ValueError(
            "No text was extracted. The document may be scanned, image-only, empty, or protected."
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")
    temporary_output.write_text(markdown, encoding="utf-8")
    temporary_output.replace(output_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert one local file to Markdown")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        convert(arguments.input, arguments.output)
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
