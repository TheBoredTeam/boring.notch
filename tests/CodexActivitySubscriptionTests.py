# SPDX-License-Identifier: GPL-3.0-only

import json
from pathlib import Path
import socket
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "script"))
from codex_activity_bridge import DesktopObserver
from CodexActivityBridgeTests import patch, snapshot


class SubscriptionTests(unittest.TestCase):
    def setUp(self):
        self.observer = DesktopObserver()
        self.observer.client_id = "synthetic-client"
        self.observer.projection.connected = True
        self.sent = []
        self.observer.send = self.sent.append

    def tearDown(self):
        self.observer.server_discovery.close()
        self.observer.thread_discovery.close()

    def test_known_inactive_is_not_refreshed_without_a_file_change(self):
        self.observer.refresh_subscriptions({"one": 99}, 100)
        self.observer.projection.consume(snapshot("idle"), 101)
        self.sent.clear()
        self.observer.refresh_subscriptions({"one": 99}, 160)
        self.assertEqual(self.sent, [])
        self.assertIn("one", self.observer.subscribed)
        self.assertEqual(self.observer.projection.summary(160)["phase"], "idle")

    def test_idle_task_resumes_from_runtime_patch_without_a_rollout_write(self):
        self.observer.sock, writer = socket.socketpair()
        self.addCleanup(writer.close)
        self.addCleanup(self.observer.reset)
        self.observer.refresh_subscriptions({"one": 99}, 100)

        def deliver(message, now):
            data = json.dumps(message).encode()
            writer.sendall(struct.pack("<I", len(data)) + data)
            self.observer.receive(now)

        deliver(snapshot("idle"), 101)
        self.assertIn("one", self.observer.subscribed)
        self.sent.clear()
        self.observer.refresh_subscriptions({"one": 99}, 160)
        self.assertEqual(self.sent, [])
        deliver(patch({"type": "active", "activeFlags": []}), 161)
        self.assertEqual(self.observer.projection.summary(161)["activeCount"], 1)
        self.assertIn("one", self.observer.subscribed)
        deliver(patch({"type": "idle"}, base=2, revision=3), 162)
        self.observer.refresh_subscriptions({"one": 99}, 220)
        self.assertEqual(self.observer.projection.summary(220)["phase"], "idle")
        self.assertIn("one", self.observer.subscribed)
        self.assertEqual(self.sent, [])

    def test_resuming_an_old_task_refollows_after_its_mtime_changes(self):
        self.observer.refresh_subscriptions({"one": 99}, 100)
        self.observer.projection.consume(snapshot("idle"), 101)
        self.observer.unfollow("one")
        self.sent.clear()
        self.observer.refresh_subscriptions({"one": 102}, 103)
        self.assertEqual(len(self.sent), 1)
        self.assertTrue(self.sent[0]["params"]["following"])

    def test_active_and_waiting_quiet_tasks_refresh_before_expiration(self):
        for flags in [[], ["waitingOnUserInput"]]:
            self.observer.refresh_subscriptions({"one": 99}, 100)
            self.observer.projection.consume(snapshot(flags=flags), 101)
            self.sent.clear()
            self.observer.refresh_subscriptions({"one": 99}, 130)
            self.assertEqual(self.sent, [])
            self.observer.refresh_subscriptions({"one": 99}, 131)
            self.assertTrue(self.sent[0]["params"]["following"])
            self.assertEqual(self.observer.projection.summary(131)["activeCount"], 1)
            self.observer.reset()

    def test_pending_follow_has_a_lease_and_bounded_retry(self):
        self.observer.refresh_subscriptions({"one": 99}, 100)
        self.observer.refresh_subscriptions({"one": 99}, 108)
        self.assertFalse(self.sent[-1]["params"]["following"])
        self.sent.clear()
        self.observer.refresh_subscriptions({"one": 99}, 137)
        self.assertEqual(self.sent, [])
        self.observer.refresh_subscriptions({"one": 99}, 138)
        self.assertTrue(self.sent[0]["params"]["following"])

    def test_owner_hint_without_a_rollout_also_expires(self):
        self.observer.follow("hint-only", 100)
        self.observer.refresh_subscriptions({}, 108)
        self.assertNotIn("hint-only", self.observer.subscribed)
        self.assertFalse(self.sent[-1]["params"]["following"])
        self.sent.clear()
        self.observer.refresh_subscriptions({}, 138)
        self.assertTrue(self.sent[0]["params"]["following"])

    def test_resume_probe_retries_when_old_idle_owner_does_not_reply(self):
        self.observer.projection.consume(snapshot("idle"), 101)
        self.observer.probed_versions["one"] = 99
        self.observer.refresh_subscriptions({"one": 102}, 103)
        self.assertNotIn("one", self.observer.projection.threads)
        self.observer.refresh_subscriptions({"one": 102}, 111)
        self.sent.clear()
        self.observer.refresh_subscriptions({"one": 102}, 141)
        self.assertTrue(self.sent[0]["params"]["following"])

    def test_fresh_follow_drops_old_idle_but_preserves_active_freshness(self):
        self.observer.projection.consume(snapshot("idle"), 101)
        self.observer.follow("one", 102)
        self.assertNotIn("one", self.observer.projection.threads)
        self.observer.projection.consume(snapshot(), 103)
        self.observer.follow("one", 104)
        self.assertEqual(self.observer.projection.threads["one"]["seen"], 103)

    def test_file_change_during_snapshot_is_not_swallowed(self):
        self.observer.refresh_subscriptions({"one": 99}, 100)
        self.observer.projection.consume(snapshot("idle"), 101)
        self.observer.unfollow("one")
        self.observer.refresh_subscriptions({"one": 100.5}, 102)
        self.assertTrue(self.sent[-1]["params"]["following"])

    def test_recent_candidates_are_probed_first(self):
        self.observer.refresh_subscriptions({"old": 10, "recent": 99}, 100)
        self.assertEqual([message["params"]["conversationId"] for message in self.sent], ["recent", "old"])

    def test_hidden_task_releases_subscription_and_ignores_follow_hints(self):
        self.observer.sock, writer = socket.socketpair()
        self.addCleanup(writer.close)
        self.addCleanup(self.observer.reset)
        self.observer.refresh_subscriptions({"one": 99}, 100)
        hidden = snapshot(metadata={"threadSource": "subagent", "parentThreadId": "parent"})
        data = json.dumps(hidden).encode()
        writer.sendall(struct.pack("<I", len(data)) + data)
        self.observer.receive(101)
        self.observer.refresh_subscriptions({"one": 99}, 102)
        self.assertNotIn("one", self.observer.subscribed)
        self.assertFalse(self.sent[-1]["params"]["following"])
        self.sent.clear()
        hint = {"type": "broadcast", "method": "thread-stream-following-status-requested",
                "params": {"hostId": "local", "conversationId": "one"}}
        data = json.dumps(hint).encode()
        writer.sendall(struct.pack("<I", len(data)) + data)
        self.observer.receive(103)
        self.observer.refresh_subscriptions({"one": 104}, 160)
        self.assertEqual(self.sent, [])
        self.assertNotIn("one", self.observer.subscribed)
        self.assertEqual(self.observer.projection.summary(160)["activeCount"], 0)

    def test_archived_task_stays_unfollowed_until_unarchive(self):
        self.observer.sock, writer = socket.socketpair()
        self.addCleanup(writer.close)
        self.addCleanup(self.observer.reset)

        def deliver(message, now):
            data = json.dumps(message).encode()
            writer.sendall(struct.pack("<I", len(data)) + data)
            self.observer.receive(now)

        self.observer.refresh_subscriptions({"one": 99}, 100)
        deliver(snapshot(), 101)
        event = {"type": "broadcast", "method": "thread-archived",
                 "params": {"hostId": "local", "conversationId": "one"}}
        deliver(event, 102)
        self.assertNotIn("one", self.observer.subscribed)
        self.assertFalse(self.sent[-1]["params"]["following"])
        self.sent.clear()
        deliver(snapshot(revision=2), 103)
        deliver({"type": "broadcast", "method": "thread-stream-following-status-requested",
                 "params": {"hostId": "local", "conversationId": "one"}}, 104)
        self.observer.refresh_subscriptions({"one": 104}, 160)
        self.assertEqual(self.sent, [])
        self.assertEqual(self.observer.projection.summary(160)["activeCount"], 0)
        self.observer.next_probe["one"] = 300
        event["method"] = "thread-unarchived"
        deliver(event, 161)
        self.assertEqual(len(self.sent), 1)
        self.assertTrue(self.sent[0]["params"]["following"])
        deliver(snapshot(revision=3), 163)
        self.assertEqual(self.observer.projection.summary(163)["activeCount"], 1)

    def test_reset_clears_activity_and_discovery_fingerprints(self):
        self.observer.refresh_subscriptions({"one": 99}, 100)
        self.observer.projection.consume(snapshot(), 101)
        self.observer.reset()
        self.assertFalse(self.observer.subscribed)
        self.assertFalse(self.observer.probed_versions)
        self.assertEqual(self.observer.projection.summary(102)["activeCount"], 0)


if __name__ == "__main__":
    unittest.main()
