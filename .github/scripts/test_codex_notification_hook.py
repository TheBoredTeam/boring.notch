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
import contextlib
import ctypes
import hashlib
import hmac
import io
import json
import os
import subprocess
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


def add_extended_read_acl(path: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    libc.acl_from_text.argtypes = [ctypes.c_char_p]
    libc.acl_from_text.restype = ctypes.c_void_p
    libc.acl_set_fd_np.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    libc.acl_free.argtypes = [ctypes.c_void_p]

    access_list = libc.acl_from_text(
        b"!#acl 1\n"
        b"group:ABCDEFAB-CDEF-ABCD-EFAB-CDEF00000014:staff:20:allow:read\n"
    )
    if not access_list:
        raise OSError(ctypes.get_errno(), "acl_from_text failed")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
        try:
            if libc.acl_set_fd_np(descriptor, access_list, 0x100) != 0:
                raise OSError(ctypes.get_errno(), "acl_set_fd_np failed")
        finally:
            os.close(descriptor)
    finally:
        libc.acl_free(access_list)


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
    def test_lifecycle_entrypoint_forwards_events_without_inventing_outcomes(self) -> None:
        for event in ("Stop", "Interrupt", "UserPromptSubmit"):
            with self.subTest(event=event):
                namespace = embedded_hook_namespace()
                source = {
                    "hook_event_name": event, "session_id": "synthetic", "turn_id": "turn",
                    "last_assistant_message": "error: quoted example", "prompt": "Synthetic prompt",
                    "status": "failed", "error": "unverified outcome",
                }
                sent = []
                namespace["sys"] = types.SimpleNamespace(stdin=io.StringIO(json.dumps(source)))
                namespace["thread_metadata"] = lambda _: {}
                namespace["open_notch"] = lambda payload: sent.append(payload.copy()) or True
                entrypoint = ast.parse(embedded_hook_source()).body[-1]
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    exec(compile(ast.Module(body=[entrypoint], type_ignores=[]), "hook", "exec"), namespace)
                self.assertEqual(json.loads(output.getvalue()), {})
                self.assertEqual(len(sent), 1)
                self.assertEqual(sent[0]["hook_event_name"], event)
                self.assertEqual(sent[0]["turn_id"], "turn")
                self.assertNotIn("status", sent[0])
                self.assertNotIn("error", sent[0])

    def test_open_notch_targets_codex_event_and_signs_payload(self) -> None:
        namespace = embedded_hook_namespace()
        namespace["APP_BUNDLE_PATH"] = "/tmp/Fixture App.app"
        hook = namespace["open_notch"]
        self.assertTrue(callable(hook))

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            secret = bytes(range(32))
            secret_path = temporary_path / "boring-notch-notify.secret"
            secret_path.write_bytes(secret)
            secret_path.chmod(0o600)
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
            bundle_flag_index = command.index("-a")
            self.assertEqual(command[bundle_flag_index + 1], namespace["APP_BUNDLE_PATH"])
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

    def test_same_turn_permission_requests_receive_distinct_signed_ids(self) -> None:
        namespace = embedded_hook_namespace()
        hook = namespace["open_notch"]

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            secret_path = temporary_path / "boring-notch-notify.secret"
            secret_path.write_bytes(bytes(range(32)))
            secret_path.chmod(0o600)
            namespace["__file__"] = str(temporary_path / "boring-notch-notify.py")
            commands: list[list[str]] = []

            def fake_run(args: list[str], **_: object) -> types.SimpleNamespace:
                commands.append(args)
                return types.SimpleNamespace(returncode=0)

            original_run = namespace["subprocess"].run
            namespace["subprocess"].run = fake_run
            try:
                for command in ("first", "second"):
                    self.assertTrue(hook({
                        "hook_event_name": "PermissionRequest",
                        "session_id": "shared-session",
                        "turn_id": "shared-turn",
                        "tool_input": {"command": command},
                    }))
            finally:
                namespace["subprocess"].run = original_run

            request_ids = []
            for command in commands:
                encoded = parse_qs(urlparse(command[-1]).query)["payload"][0]
                padded = encoded + "=" * (-len(encoded) % 4)
                payload = json.loads(base64.urlsafe_b64decode(padded))
                request_ids.append(payload["boring_notch_auth"]["nonce"])

            self.assertEqual(len(request_ids), 2)
            self.assertEqual(len(set(request_ids)), 2)
            self.assertTrue(all(len(request_id) == 32 for request_id in request_ids))

    def test_open_notch_rejects_broad_secret_permissions(self) -> None:
        namespace = embedded_hook_namespace()
        hook = namespace["open_notch"]

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            secret_path = temporary_path / "boring-notch-notify.secret"
            secret_path.write_bytes(bytes(range(32)))
            secret_path.chmod(0o644)
            namespace["__file__"] = str(temporary_path / "boring-notch-notify.py")

            calls: list[list[str]] = []

            def fake_run(args: list[str], **_: object) -> types.SimpleNamespace:
                calls.append(args)
                return types.SimpleNamespace(returncode=0)

            original_run = namespace["subprocess"].run
            namespace["subprocess"].run = fake_run
            try:
                self.assertFalse(
                    hook({"hook_event_name": "Stop", "session_id": "unsafe"})
                )
            finally:
                namespace["subprocess"].run = original_run

            self.assertEqual(calls, [])

    def test_open_notch_rejects_secret_symlink_replacement(self) -> None:
        namespace = embedded_hook_namespace()
        hook = namespace["open_notch"]

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            target_path = temporary_path / "target"
            target_path.write_bytes(bytes(range(32)))
            target_path.chmod(0o600)
            (temporary_path / "boring-notch-notify.secret").symlink_to(target_path)
            namespace["__file__"] = str(temporary_path / "boring-notch-notify.py")

            calls: list[list[str]] = []

            def fake_run(args: list[str], **_: object) -> types.SimpleNamespace:
                calls.append(args)
                return types.SimpleNamespace(returncode=0)

            original_run = namespace["subprocess"].run
            namespace["subprocess"].run = fake_run
            try:
                self.assertFalse(
                    hook({"hook_event_name": "Stop", "session_id": "unsafe"})
                )
            finally:
                namespace["subprocess"].run = original_run

            self.assertEqual(calls, [])

    def test_open_notch_rejects_secret_with_extended_acl(self) -> None:
        namespace = embedded_hook_namespace()
        hook = namespace["open_notch"]

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            secret_path = temporary_path / "boring-notch-notify.secret"
            secret_path.write_bytes(bytes(range(32)))
            secret_path.chmod(0o600)
            add_extended_read_acl(secret_path)
            namespace["__file__"] = str(temporary_path / "boring-notch-notify.py")

            calls: list[list[str]] = []

            def fake_run(args: list[str], **_: object) -> types.SimpleNamespace:
                calls.append(args)
                return types.SimpleNamespace(returncode=0)

            original_run = namespace["subprocess"].run
            namespace["subprocess"].run = fake_run
            try:
                self.assertFalse(
                    hook({"hook_event_name": "Stop", "session_id": "unsafe"})
                )
            finally:
                namespace["subprocess"].run = original_run

            self.assertEqual(calls, [])

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

class CodexResponseDeliveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # Compile the real Swift parser once; only synthetic URLs enter this process.
        cls.temporary = tempfile.TemporaryDirectory()
        directory = Path(cls.temporary.name)
        driver = directory / "main.swift"
        driver.write_text(r'''
import Foundation
import CryptoKit
let input = FileHandle.standardInput.readDataToEndOfFile()
let components = URLComponents(string: String(decoding: input, as: UTF8.self))!
let encoded = components.queryItems!.first { $0.name == "payload" }!.value!
let signature = components.queryItems!.first { $0.name == "signature" }!.value!
let key = SymmetricKey(data: Data((0..<32).map(UInt8.init)))
let expected = Data(HMAC<SHA256>.authenticationCode(for: Data(encoded.utf8), using: key))
    .base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
guard signature == expected else { exit(2) }
var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
var state = CodexNotificationState()
state.reduce(try CodexHookEventParser.parse(Data(base64Encoded: base64)!))
let notice = state.visibleNotification()!
let preview = notice.responsePreview
let result: [String: Any] = [
    "digest": SHA256.hash(data: Data((preview?.source ?? "").utf8)).map { String(format: "%02x", $0) }.joined(),
    "code_points": preview?.source.unicodeScalars.count ?? 0,
    "truncated": preview?.isTruncated ?? false,
    "status": notice.status.title,
    "session": notice.sessionID,
]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
''', encoding="utf-8")
        cls.driver = directory / "response-delivery"
        compiled = subprocess.run([
            "swiftc", "-module-cache-path", "/tmp/boring-notch-clang-module-cache",
            str(REPOSITORY_ROOT / "boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift"),
            str(driver), "-o", str(cls.driver),
        ], capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError("Synthetic Swift response-delivery driver failed to compile: " + compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def deliver(self, source: str, **fields: object) -> tuple[dict, dict, str]:
        namespace = embedded_hook_namespace()
        calls = []
        namespace["read_hook_secret"] = lambda _: bytes(range(32))
        original_run = namespace["subprocess"].run
        namespace["subprocess"].run = lambda args, **_: calls.append(args) or types.SimpleNamespace(returncode=0)
        payload = {
            "hook_event_name": "Stop", "session_id": "synthetic-chat", "turn_id": "synthetic-turn",
            "last_assistant_message": source, **fields,
        }
        try:
            self.assertTrue(namespace["open_notch"](payload))
        finally:
            namespace["subprocess"].run = original_run
        self.assertEqual(len(calls), 1)
        url = calls[0][-1]
        self.assertLessEqual(len(url.encode("utf-8")), namespace["MAX_EVENT_URL_BYTES"])
        encoded = parse_qs(urlparse(url).query)["payload"][0]
        serialized = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        self.assertLessEqual(len(serialized), namespace["MAX_PAYLOAD_BYTES"])
        # Exercise a real process argument of the same size as /usr/bin/open's URL.
        subprocess.run(["/usr/bin/true", url], check=True, capture_output=True)
        parsed = subprocess.run([str(self.driver)], input=url, capture_output=True, text=True, check=True)
        return json.loads(serialized), json.loads(parsed.stdout), url

    def test_source_cap_survives_python_url_and_swift_without_unicode_or_markdown_loss(self) -> None:
        for source in [
            "# Heading\n\n| A | B |\n| --- | --- |\n| 你好 | café |\n\n```swift\nlet x = 1\n```\n",
            "a" * 15_999, "a" * 16_000, "a" * 16_001,
            "🙂" * 16_001, "e\u0301" * 8_001, '\\"\n\x00' * 4_001,
        ]:
            with self.subTest(code_points=len(source)):
                sent, parsed, _ = self.deliver(source)
                expected = source[:16_000]
                self.assertEqual(sent["last_assistant_message"], expected)
                self.assertEqual(parsed["digest"], hashlib.sha256(expected.encode("utf-8")).hexdigest())
                self.assertEqual(parsed["code_points"], len(expected))
                self.assertEqual(parsed["truncated"], len(source) > 16_000)
                self.assertEqual(parsed["session"], "synthetic-chat")

    def test_delivery_budget_shortens_response_instead_of_dropping_notification(self) -> None:
        source = "🙂" * 16_000
        sent, parsed, _ = self.deliver(source, tool_input={"command": "x" * 90_000})
        retained = sent["last_assistant_message"]
        self.assertGreater(len(retained), 0)
        self.assertLess(len(retained), 16_000)
        self.assertEqual(retained, source[:len(retained)])
        self.assertTrue(parsed["truncated"])
        self.assertEqual(parsed["status"], "Response ready")
        self.assertEqual(parsed["digest"], hashlib.sha256(retained.encode("utf-8")).hexdigest())

    def test_entrypoint_no_longer_clips_the_response_to_four_thousand(self) -> None:
        namespace = embedded_hook_namespace()
        source = {"hook_event_name": "Stop", "session_id": "synthetic", "last_assistant_message": "x" * 5_000}
        sent = []
        namespace["sys"] = types.SimpleNamespace(stdin=io.StringIO(json.dumps(source)))
        namespace["thread_metadata"] = lambda _: {}
        namespace["open_notch"] = lambda payload: sent.append(payload.copy()) or True
        entrypoint = ast.parse(embedded_hook_source()).body[-1]
        with contextlib.redirect_stdout(io.StringIO()):
            exec(compile(ast.Module(body=[entrypoint], type_ignores=[]), "hook", "exec"), namespace)
        self.assertEqual(sent[0]["last_assistant_message"], source["last_assistant_message"])

    def test_response_url_budget_does_not_change_large_permission_delivery(self) -> None:
        namespace = embedded_hook_namespace()
        calls = []
        namespace["read_hook_secret"] = lambda _: bytes(range(32))
        original_run = namespace["subprocess"].run
        namespace["subprocess"].run = lambda args, **_: calls.append(args) or types.SimpleNamespace(returncode=0)
        try:
            self.assertTrue(namespace["open_notch"]({
                "hook_event_name": "PermissionRequest", "session_id": "synthetic",
                "tool_input": {"command": "x" * 96_000, "description": "x" * 16_000},
            }))
        finally:
            namespace["subprocess"].run = original_run
        self.assertEqual(len(calls), 1)
        self.assertGreater(len(calls[0][-1]), namespace["MAX_EVENT_URL_BYTES"])


if __name__ == "__main__":
    unittest.main()
