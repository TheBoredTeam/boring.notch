#!/usr/bin/env python3
"""Unit tests for the local-only MarkItDown wrapper."""

from __future__ import annotations

import importlib.util
import mimetypes
import os
import socket
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "markitdown_local", ROOT / "scripts" / "markitdown_local.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalWrapperTests(unittest.TestCase):
    def test_supported_extensions_are_explicit(self) -> None:
        self.assertIn(".pdf", MODULE.SUPPORTED_EXTENSIONS)
        self.assertIn(".docx", MODULE.SUPPORTED_EXTENSIONS)
        self.assertNotIn(".exe", MODULE.SUPPORTED_EXTENSIONS)

    def test_runtime_lock_excludes_cloud_and_optional_remote_dependencies(self) -> None:
        requirements = (
            ROOT / "requirements" / "markitdown-runtime.txt"
        ).read_text(encoding="utf-8").lower()
        self.assertIn("markitdown==0.1.7", requirements)
        for excluded in (
            "openai==",
            "azure-ai-documentintelligence==",
            "azure-identity==",
            "youtube-transcript-api==",
            "speechrecognition==",
        ):
            self.assertNotIn(excluded, requirements)

    def test_network_connections_are_denied_and_proxies_removed(self) -> None:
        original_socket = socket.socket
        original_create_connection = socket.create_connection
        with mock.patch.dict(os.environ, {"HTTPS_PROXY": "http://127.0.0.1:9"}, clear=False):
            try:
                MODULE._disable_network()
                with self.assertRaisesRegex(RuntimeError, "Network access is disabled"):
                    socket.create_connection(("127.0.0.1", 9))
                self.assertNotIn("HTTPS_PROXY", os.environ)
                self.assertEqual(os.environ["NO_PROXY"], "*")
            finally:
                socket.socket = original_socket
                socket.create_connection = original_create_connection

    def test_mime_initialization_never_reads_system_databases(self) -> None:
        original_knownfiles = mimetypes.knownfiles
        try:
            mimetypes.knownfiles = ["/etc/apache2/mime.types"]
            MODULE._initialize_sandbox_safe_mimetypes()
            self.assertEqual(mimetypes.knownfiles, [])
        finally:
            mimetypes.knownfiles = original_knownfiles

    def test_conversion_writes_separate_output_and_preserves_source(self) -> None:
        class Result:
            markdown = "# Converted locally\n"

        class FakeMarkItDown:
            def __init__(self, *, enable_plugins: bool):
                self.enable_plugins = enable_plugins

            def convert_local(self, source: Path) -> Result:
                self.source = source
                return Result()

        fake_module = types.SimpleNamespace(MarkItDown=FakeMarkItDown)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.pdf"
            output = root / "output.md"
            source.write_bytes(b"original source bytes")
            with mock.patch.dict(sys.modules, {"markitdown": fake_module}):
                MODULE.convert(source, output)
            self.assertEqual(source.read_bytes(), b"original source bytes")
            self.assertEqual(output.read_text(encoding="utf-8"), "# Converted locally\n")

    def test_source_cannot_be_used_as_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.txt"
            source.write_text("preserve me", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "must be different"):
                MODULE.convert(source, source)

            self.assertEqual(source.read_text(encoding="utf-8"), "preserve me")


if __name__ == "__main__":
    unittest.main()
