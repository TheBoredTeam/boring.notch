# SPDX-License-Identifier: GPL-3.0-only

import io
import json
from pathlib import Path
import random
import socket
import struct
import sys
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "script"))
from codex_activity_json import ActivityJSONReader, CHUNK_BYTES
from codex_activity_bridge import ActivityProjection, DesktopObserver
from CodexActivityBridgeTests import snapshot, patch


def decode(value, chunk=CHUNK_BYTES):
    data = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
    source = io.BytesIO(data)
    return ActivityJSONReader(lambda size: source.read(min(size, chunk)), len(data)).decode()


class StreamingJSONTests(unittest.TestCase):
    def test_matches_authoritative_projection_with_fragmented_frames(self):
        sequence = [snapshot(), patch("idle", path=["threadRuntimeStatus", "type"]),
                    snapshot(flags=["waitingOnApproval"]),
                    patch("unrelated", path=["turnHistory", "items", 1]),
                    patch(["waitingOnUserInput"], path=["threadRuntimeStatus", "activeFlags"], base=2, revision=3),
                    patch("idle", path=["threadRuntimeStatus", "type"], base=30),
                    snapshot("notLoaded"), snapshot(owner="new-owner"),
                    {"type": "broadcast", "method": "client-status-changed",
                     "params": {"clientId": "new-owner", "status": "disconnected"}}]
        for chunk in [1, 2, 3, 7, 31, 1024, CHUNK_BYTES]:
            full, projected = ActivityProjection(), ActivityProjection()
            full.connected = projected.connected = True
            for now, message in enumerate(sequence, 100):
                self.assertEqual(full.consume(message, now), projected.consume(decode(message, chunk), now))
                self.assertEqual(full.summary(now), projected.summary(now))

    def test_metadata_survives_large_ignored_text_before_and_after_status(self):
        for chunk in [7, CHUNK_BYTES]:
            message = snapshot()
            state = message["params"]["change"]["conversationState"]
            state["turns"] = [{"text": ("private \"text\" \\ 💚\n" * 2000)}]
            state["after"] = "another private value" * 2000
            projected = decode(message, chunk)
            retained = projected["params"]["change"]["conversationState"]
            self.assertEqual(retained, {"threadRuntimeStatus": {"type": "active", "activeFlags": []},
                                        "source": "vscode", "threadSource": "user"})
            self.assertLess(len(json.dumps(projected)), 1024)

    def test_all_key_orders_and_unicode_escapes(self):
        rng = random.Random(7)
        def shuffled(value):
            if isinstance(value, dict):
                items = list(value.items())
                rng.shuffle(items)
                return {key: shuffled(item) for key, item in items}
            if isinstance(value, list):
                return [shuffled(item) for item in value]
            return value
        for _ in range(60):
            message = shuffled(snapshot(owner="owner-💚-\\-\""))
            projected = decode(json.dumps(message, ensure_ascii=True).encode(), rng.randint(1, 50))
            self.assertEqual(projected["sourceClientId"], message["sourceClientId"])
            self.assertEqual(projected["params"]["conversationId"], "one")

    def test_content_patch_values_are_bounded_in_any_key_order(self):
        for value in ["x" * 100_000, list(range(10_000)), [{}] * 1000,
                      {"turns": ["private" * 1000] * 100}]:
            for value_first in [True, False]:
                item = {"value": value, "path": ["turnHistory"], "op": "replace"}
                if not value_first:
                    item = dict(reversed(list(item.items())))
                message = patch(None)
                message["params"]["change"]["patches"] = [item, {
                    "value": {"type": "idle"}, "path": ["threadRuntimeStatus"], "op": "replace"}]
                projected = decode(message)
                self.assertEqual(projected["params"]["change"]["patches"], [{
                    "value": {"type": "idle"}, "path": ["threadRuntimeStatus"], "op": "replace"}])

    def test_long_nested_status_path_still_requests_authoritative_snapshot(self):
        message = patch("ignored", path=["threadRuntimeStatus", "activeFlags", 0] + ["nested"] * 300)
        projection = ActivityProjection()
        projection.connected = True
        projection.consume(snapshot(), 100)
        self.assertEqual(projection.consume(decode(message), 101), "one")
        self.assertEqual(projection.summary(101)["activeCount"], 0)

    def test_visibility_patches_invalidate_count_until_complete_snapshot(self):
        for chunk in [1, 7, CHUNK_BYTES]:
            for path, value in [(["source"], "cli"), (["source", "subagent"], {}),
                                (["threadSource"], "subagent"), (["parentThreadId"], "parent"),
                                (["ephemeral"], True), (["sideConversation"], True)]:
                for operation in ["replace", "remove"]:
                    with self.subTest(chunk=chunk, path=path, operation=operation):
                        projection = ActivityProjection()
                        projection.connected = True
                        projection.consume(decode(snapshot(), chunk), 100)
                        message = patch(value, path=path)
                        item = message["params"]["change"]["patches"][0]
                        item["op"] = operation
                        if operation == "remove":
                            del item["value"]
                        self.assertEqual(projection.consume(decode(message, chunk), 101), "one")
                        self.assertEqual(projection.summary(101)["activeCount"], 0)
                        projection.consume(decode(snapshot(metadata={"sideConversation": True}, revision=3), chunk), 102)
                        self.assertEqual(projection.summary(102)["activeCount"], 0)
                        projection.consume(decode(snapshot(revision=4), chunk), 103)
                        self.assertEqual(projection.summary(103)["activeCount"], 1)

    def test_malformed_visibility_metadata_is_not_normalized_into_visible_task(self):
        for metadata in [{"source": {"subagent": {"thread_spawn": {"parent_thread_id": "parent"}}}},
                         {"parentThreadId": {}}, {"parentThreadId": []},
                         {"threadSource": {}}, {"threadSource": []},
                         {"ephemeral": {}}, {"sideConversation": []},
                         {"source": "x" * 1000}, {"parentThreadId": "x" * 1000},
                         {"threadSource": "x" * 1000}]:
            for chunk in [1, CHUNK_BYTES]:
                with self.subTest(metadata=metadata, chunk=chunk):
                    projection = ActivityProjection()
                    projection.connected = True
                    projection.consume(decode(snapshot(metadata=metadata), chunk), 100)
                    self.assertEqual(projection.summary(100)["activeCount"], 0)

    def test_invalid_status_shapes_fail_closed_without_crashing(self):
        for value in [None, [], 3, "unexpected", {"type": []}, {"type": "active", "activeFlags": [{}]}]:
            projection = ActivityProjection()
            projection.connected = True
            message = snapshot()
            message["params"]["change"]["conversationState"]["threadRuntimeStatus"] = value
            projection.consume(decode(message), 100)
            self.assertEqual(projection.summary(100)["activeCount"], 0)
        for message in [{"type": "broadcast", "params": None},
                        {"type": "broadcast", "params": {"change": None}}]:
            ActivityProjection().consume(decode(message), 100)

    def test_protocol_handshake_and_discovery_fields_are_retained(self):
        for message in [{"type": "response", "method": "initialize", "result": {"clientId": "observer"}},
                        {"type": "client-discovery-request", "requestId": "request"},
                        {"type": "broadcast", "method": "ipc-connection-reset"}]:
            self.assertEqual(decode(message, 1), message)

    def test_malformed_or_truncated_json_is_rejected(self):
        for data in [b'', b'[]', b'{} {}', b'{"type":}', b'{"type":1,}',
                     b'{"ignored":[1,]}', b'{"ignored":"bad\\q"}',
                     b'{"ignored":"bad\\u0z00"}', b'{"ignored":"bad\n"}',
                     b'{"ignored":"\xff"}', b'{"ignored":{"a" 1}}']:
            with self.subTest(data=data):
                with self.assertRaises((ValueError, UnicodeError)):
                    decode(data, 1)
        for cut in range(len(b'{"type":"broadcast"}')):
            with self.assertRaises(ValueError):
                decode(b'{"type":"broadcast"}'[:cut], 2)

    def test_reader_does_not_read_into_the_next_frame(self):
        first, second = b'{"type":"one"}', b'{"type":"two"}'
        stream = io.BytesIO(first + second)
        self.assertEqual(ActivityJSONReader(stream.read, len(first)).decode(), {"type": "one"})
        self.assertEqual(stream.read(), second)

    def test_socket_observer_accepts_fragmented_header_and_multiple_frames(self):
        observer = DesktopObserver()
        observer.sock, writer = socket.socketpair()
        observer.sock.settimeout(2)
        def send():
            for message in [snapshot(), patch({"type": "idle"})]:
                data = json.dumps(message).encode()
                for byte in struct.pack("<I", len(data)):
                    writer.sendall(bytes([byte]))
                writer.sendall(data)
            writer.close()
        thread = threading.Thread(target=send)
        thread.start()
        try:
            observer.projection.connected = True
            observer.receive(100)
            self.assertEqual(observer.projection.summary(100)["activeCount"], 1)
            observer.receive(101)
            self.assertEqual(observer.projection.summary(101)["activeCount"], 0)
        finally:
            observer.reset()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
