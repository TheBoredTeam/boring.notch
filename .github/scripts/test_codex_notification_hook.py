#!/usr/bin/env python3
"""Exercise the repository-owned Codex hook boundary without launching the app.

The hook is embedded in the unsandboxed XPC helper as a Swift raw string. These
tests extract the production string, execute its definitions, and drive the real
launch and permission relay code with local fakes and in-memory requests. Swift
authentication, configuration, trust, and replay behavior is covered by the
SwiftPM test target.
"""

from __future__ import annotations

import ast
import base64
import hashlib
import hmac
import io
import json
from pathlib import Path
import tempfile
import textwrap
import types
import unittest
from typing import Optional
from urllib.parse import parse_qs, urlparse


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
HELPER_SOURCE_PATH = REPOSITORY_ROOT / "BoringNotchXPCHelper" / "BoringNotchXPCHelper.swift"
SCRIPT_START = 'private static let codexNotificationScript = #"""\n'
SCRIPT_END = '\n    """#'


def embedded_hook_source() -> str:
    source = HELPER_SOURCE_PATH.read_text(encoding="utf-8")
    start = source.index(SCRIPT_START) + len(SCRIPT_START)
    end = source.index(SCRIPT_END, start)
    return textwrap.dedent(source[start:end])


def embedded_hook_namespace() -> dict[str, object]:
    """Load only definitions from the embedded script, not its stdin entrypoint."""
    tree = ast.parse(embedded_hook_source(), filename=str(HELPER_SOURCE_PATH))
    definition_nodes = [
        node
        for node in tree.body
        if isinstance(
            node,
            (
                ast.ClassDef,
                ast.FunctionDef,
                ast.Import,
                ast.ImportFrom,
                ast.Assign,
            ),
        )
    ]
    module = ast.Module(body=definition_nodes, type_ignores=[])
    namespace: dict[str, object] = {
        "__file__": str(HELPER_SOURCE_PATH),
        "__name__": "codex_notification_hook_test",
    }
    exec(compile(module, str(HELPER_SOURCE_PATH), "exec"), namespace)
    return namespace


class CodexNotificationHookTests(unittest.TestCase):
    def test_open_notch_targets_codex_event_and_signs_payload(self) -> None:
        namespace = embedded_hook_namespace()
        hook = namespace["open_notch"]
        self.assertTrue(callable(hook))

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            secret = bytes(range(32))
            (temporary_path / "boring-notch-notify.secret").write_bytes(secret)
            namespace["__file__"] = str(temporary_path / "boring-notch-notify.py")

            calls: list[tuple[list[str], dict[str, object]]] = []

            def fake_run(args: list[str], **kwargs: object) -> types.SimpleNamespace:
                calls.append((args, kwargs))
                return types.SimpleNamespace(returncode=0)

            original_run = namespace["subprocess"].run
            namespace["subprocess"].run = fake_run
            try:
                payload: dict[str, object] = {
                    "hook_event_name": "Stop",
                    "session_id": "session-1",
                    "last_assistant_message": "Done",
                }
                self.assertTrue(hook(payload))
            finally:
                namespace["subprocess"].run = original_run

            self.assertEqual(len(calls), 1)
            command, options = calls[0]
            self.assertEqual(command[0], "/usr/bin/open")
            self.assertIn("-g", command)
            bundle_flag_index = command.index("-b")
            self.assertEqual(command[bundle_flag_index + 1], "theboringteam.boringnotch")
            self.assertEqual(options["timeout"], 3)
            self.assertFalse(options["check"])

            self.assertEqual(command[-1].split("?", 1)[0], "boringnotch://codex-event")
            launched_url = urlparse(command[-1])
            self.assertEqual(launched_url.scheme, "boringnotch")
            self.assertEqual(launched_url.netloc, "codex-event")
            query = parse_qs(launched_url.query)
            encoded_payload = query["payload"][0]
            signature = query["signature"][0]
            expected_signature = base64.urlsafe_b64encode(
                hmac.new(secret, encoded_payload.encode("ascii"), hashlib.sha256).digest()
            ).decode("ascii").rstrip("=")
            self.assertTrue(hmac.compare_digest(signature, expected_signature))

            padded_payload = encoded_payload + "=" * (-len(encoded_payload) % 4)
            decoded_payload = json.loads(base64.urlsafe_b64decode(padded_payload))
            authentication = decoded_payload["boring_notch_auth"]
            self.assertIsInstance(authentication["timestamp"], (int, float))
            self.assertEqual(len(authentication["nonce"]), 32)

    def test_permission_relay_rejects_bad_tokens_and_allows_one_decision(self) -> None:
        namespace = embedded_hook_namespace()
        handler_type = namespace["PermissionDecisionHandler"]
        server = types.SimpleNamespace(
            approval_token="test-token",
            ready=False,
            decision=None,
        )

        class Request:
            def __init__(self, body: dict[str, str]) -> None:
                encoded_body = json.dumps(body).encode("utf-8")
                self.path = "/decision"
                self.headers = {"Content-Length": str(len(encoded_body))}
                self.rfile = io.BytesIO(encoded_body)
                self.server = server
                self.status: Optional[int] = None

            def respond(self, status: int) -> None:
                self.status = status

        def post(body: dict[str, str]) -> int:
            request = Request(body)
            handler_type.do_POST(request)
            self.assertIsNotNone(request.status)
            return request.status

        self.assertEqual(post({"token": "wrong", "decision": "allow"}), 403)
        self.assertEqual(post({"token": "test-token", "decision": "ready"}), 204)
        self.assertTrue(server.ready)
        self.assertEqual(post({"token": "test-token", "decision": "allow"}), 204)
        self.assertEqual(server.decision, "allow")
        self.assertEqual(post({"token": "test-token", "decision": "deny"}), 409)

if __name__ == "__main__":
    unittest.main()
