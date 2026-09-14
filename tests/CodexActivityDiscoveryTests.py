# SPDX-License-Identifier: GPL-3.0-only

import importlib.util
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location("activity_discovery", Path(__file__).resolve().parents[1] / "script/codex_activity_discovery.py")
discovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(discovery)


class Watch:
    def __init__(self, supported=True):
        self.supported = supported
        self.dirty = False
        self.closed = False
        self.processes = []
        self.directories = []

    def process(self, pid):
        self.processes.append(pid)
        return self.supported

    def directory(self, path):
        self.directories.append(path)
        return self.supported

    def changed(self):
        result, self.dirty = self.dirty, False
        return result

    def close(self):
        self.closed = True


def processes(parent_command="/Synthetic.app/Contents/MacOS/ChatGPT", parent_start="Mon Sep  7 12:00:00 2026"):
    return {101: (100, "Mon Sep  7 12:00:01 2026", "/Synthetic.app/Contents/Resources/codex"),
            100: (1, parent_start, parent_command)}


class ProcessDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.reader = Mock(return_value=processes())
        self.created = []
        self.supported = True

        def factory():
            watch = Watch(self.supported)
            self.created.append(watch)
            return watch

        self.cache = discovery.DesktopServerDiscovery(self.reader, lambda: self.now, factory)
        self.addCleanup(self.cache.close)

    def test_validated_identity_uses_two_process_watches(self):
        identity = self.cache.identity()
        self.assertEqual(identity[0], 101)
        self.assertEqual(identity[2], 1)
        self.assertEqual(self.created[0].processes, [101, 100])
        self.assertEqual(self.reader.call_args_list[-1].args, ((101, 100),))

    def test_stable_identity_does_not_launch_repeated_process_scans(self):
        expected = self.cache.identity()
        for self.now in range(1, 60):
            self.assertEqual(self.cache.identity(), expected)
        self.assertEqual(self.reader.call_count, 2)
        self.now = 60
        self.cache.identity()
        self.assertEqual(self.reader.call_count, 3)
        self.assertEqual(self.reader.call_args.args, ((101, 100),))

    def test_exit_or_exec_forces_generation_change_even_when_pid_is_unchanged(self):
        before = self.cache.identity()
        self.created[-1].dirty = True
        after = self.cache.identity()
        self.assertEqual(before[:2], after[:2])
        self.assertGreater(after[2], before[2])
        self.assertTrue(self.created[0].closed)

    def test_exit_clears_identity(self):
        self.cache.identity()
        self.reader.return_value = {}
        self.created[-1].dirty = True
        self.assertIsNone(self.cache.identity())

    def test_parent_identity_change_is_not_hidden_by_same_server_pid(self):
        before = self.cache.identity()
        self.reader.return_value = processes(parent_start="Mon Sep  7 12:01:00 2026")
        self.now = 60
        self.assertGreater(self.cache.identity()[2], before[2])

    def test_cli_owned_server_is_rejected(self):
        self.reader.return_value = processes(parent_command="/usr/bin/python3")
        self.assertIsNone(self.cache.identity())
        self.assertEqual(self.created, [])

    def test_reparent_during_registration_is_rejected(self):
        self.reader.side_effect = [processes(), processes(parent_command="/usr/bin/python3")]
        self.assertIsNone(self.cache.identity())
        self.assertTrue(self.created[0].closed)

    def test_registration_time_exit_is_rejected(self):
        original = self.reader.side_effect

        def reader(pids=None):
            if pids is not None:
                self.created[-1].dirty = True
            return processes()

        self.reader.side_effect = reader
        self.assertIsNone(self.cache.identity())
        self.assertTrue(self.created[0].closed)
        self.reader.side_effect = original

    def test_unavailable_process_watch_uses_fast_targeted_fallback(self):
        self.supported = False
        self.cache.identity()
        self.reader.return_value = {}
        self.now = 2
        self.assertIsNone(self.cache.identity())
        self.assertEqual(self.reader.call_args_list[2].args, ((101, 100),))

    def test_reader_failure_closes_unadopted_watch(self):
        self.reader.side_effect = [processes(), OSError("synthetic failure")]
        with self.assertRaises(OSError):
            self.cache.identity()
        self.assertTrue(self.created[0].closed)

    def test_invalidate_after_ipc_failure_forces_fresh_validation(self):
        before = self.cache.identity()
        self.cache.invalidate()
        after = self.cache.identity()
        self.assertGreater(after[2], before[2])
        self.assertEqual(self.reader.call_count, 4)

    def test_missing_desktop_scan_is_rate_limited(self):
        self.reader.return_value = {}
        for self.now in [0, 0.2, 0.5, 1.9]:
            self.assertIsNone(self.cache.identity())
        self.assertEqual(self.reader.call_count, 1)
        self.now = 2
        self.cache.identity()
        self.assertEqual(self.reader.call_count, 2)


class ThreadDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "sessions"
        self.root.mkdir()
        self.created = []
        self.now = 0
        self.supported = True

        def factory():
            watch = Watch(self.supported)
            self.created.append(watch)
            return watch

        self.cache = discovery.ThreadDiscovery(self.root, lambda: self.now, factory)
        self.addCleanup(self.cache.close)

    def rollout(self, number=1, modified=100, directory="2026/09/07", segment=None):
        thread = f"00000000-0000-4000-8000-{number:012d}"
        folder = self.root / directory
        folder.mkdir(parents=True, exist_ok=True)
        suffix = f"_00000000-0000-4000-8000-{segment:012d}" if segment is not None else ""
        path = folder / f"rollout-2026-09-07T12-00-00-{thread}{suffix}.jsonl"
        path.touch()
        os.utime(path, (modified, modified))
        return path, thread

    def test_initial_discovery_never_opens_transcript_contents(self):
        _, thread = self.rollout()
        with patch("builtins.open", side_effect=AssertionError("Content read")):
            self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_recent_segment_discovers_task_whose_original_predates_server(self):
        _, thread = self.rollout(modified=10)
        self.rollout(modified=100, segment=2)
        with patch("builtins.open", side_effect=AssertionError("Content read")):
            self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_segments_deduplicate_under_task_id_using_latest_modification(self):
        _, thread = self.rollout(modified=100)
        latest, _ = self.rollout(modified=120, segment=2)
        self.rollout(modified=110, segment=3)
        self.assertEqual(self.cache.candidates(90), {thread: 120})
        os.utime(latest, (130, 130))
        with patch.object(discovery.os, "scandir", side_effect=AssertionError("Unexpected traversal")):
            self.assertEqual(self.cache.candidates(90), {thread: 130})

    def test_old_rollout_append_is_detected_without_tree_rescan(self):
        path, thread = self.rollout(modified=10)
        self.assertEqual(self.cache.candidates(90), {})
        os.utime(path, (100, 100))
        with patch.object(discovery.os, "scandir", side_effect=AssertionError("Unexpected traversal")):
            self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_new_nested_session_creation_is_discovered_on_directory_event(self):
        self.cache.candidates(90)
        _, thread = self.rollout(directory="2026/09/08")
        self.created[-1].dirty = True
        self.assertEqual(self.cache.candidates(90), {thread: 100})
        self.assertTrue(self.created[0].closed)

    def test_watches_are_registered_before_enumeration(self):
        self.rollout()
        original = os.scandir

        def scan(path):
            self.assertIn(os.fspath(path), self.created[-1].directories)
            return original(path)

        with patch.object(discovery.os, "scandir", side_effect=scan):
            self.cache.candidates(90)

    def test_renamed_and_replaced_root_clears_cached_paths(self):
        self.rollout()
        self.cache.candidates(90)
        self.root.rename(self.root.with_name("previous-sessions"))
        self.assertEqual(self.cache.candidates(90), {})
        _, thread = self.rollout(number=2)
        self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_deleted_file_does_not_survive_in_candidates(self):
        path, _ = self.rollout()
        self.cache.candidates(90)
        path.unlink()
        self.created[-1].dirty = True
        self.assertEqual(self.cache.candidates(90), {})
        self.assertEqual(self.cache.files, {})

    def test_transient_stat_failure_recovers_on_next_poll(self):
        path, thread = self.rollout()
        self.cache.candidates(90)
        original = os.stat

        def fail_file_once(name, **kwargs):
            if os.fspath(name) == os.fspath(path):
                raise OSError("synthetic transient failure")
            return original(name, **kwargs)

        with patch.object(discovery.os, "stat", side_effect=fail_file_once):
            self.assertEqual(self.cache.candidates(90), {})
        self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_watch_limit_or_registration_failure_falls_back_at_normal_cadence(self):
        self.supported = False
        self.cache.candidates(90)
        _, thread = self.rollout()
        self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_periodic_reconciliation_covers_lost_events(self):
        self.cache.candidates(90)
        _, thread = self.rollout()
        self.now = 60
        self.assertEqual(self.cache.candidates(90), {thread: 100})

    def test_candidate_filter_rechecks_server_start_without_rebuilding(self):
        _, thread = self.rollout()
        self.assertEqual(self.cache.candidates(90), {thread: 100})
        self.assertEqual(self.cache.candidates(110), {})

    def test_close_releases_directory_watches_and_metadata(self):
        self.rollout()
        self.cache.candidates(90)
        self.cache.close()
        self.assertTrue(self.created[-1].closed)
        self.assertEqual(self.cache.files, {})


@unittest.skipUnless(hasattr(select, "kqueue"), "macOS kqueue required")
class NativeNotificationTests(unittest.TestCase):
    def test_directory_creation_notification(self):
        with tempfile.TemporaryDirectory() as root:
            watch = discovery._KqueueWatch()
            self.addCleanup(watch.close)
            self.assertTrue(watch.directory(root))
            Path(root, "new-directory").mkdir()
            self.assertTrue(watch.changed())

    def test_process_exit_notification(self):
        child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.read()"], stdin=subprocess.PIPE)
        self.addCleanup(child.wait)
        self.addCleanup(child.terminate)
        watch = discovery._KqueueWatch()
        self.addCleanup(watch.close)
        self.assertTrue(watch.process(child.pid))
        child.communicate(timeout=2)
        self.assertTrue(watch.changed())

    def test_process_exec_notification(self):
        program = "import os,sys; sys.stdin.read(); os.execl('/usr/bin/true', 'true')"
        child = subprocess.Popen([sys.executable, "-c", program], stdin=subprocess.PIPE)
        self.addCleanup(child.wait)
        self.addCleanup(child.terminate)
        watch = discovery._KqueueWatch()
        self.addCleanup(watch.close)
        self.assertTrue(watch.process(child.pid))
        child.communicate(timeout=2)
        events = watch.queue.control(None, 2, 0)
        self.assertTrue(any(event.fflags & select.KQ_NOTE_EXEC for event in events))

    def test_unlimited_fd_limit_preserves_bounded_watch_budget(self):
        with patch.object(discovery.resource, "getrlimit", return_value=(discovery.resource.RLIM_INFINITY,) * 2):
            watch = discovery._KqueueWatch()
        self.addCleanup(watch.close)
        self.assertEqual(watch.directory_limit, 512)

    def test_directory_watch_limit_closes_descriptors(self):
        with tempfile.TemporaryDirectory() as root:
            watch = discovery._KqueueWatch()
            watch.directory_limit = 1
            self.assertTrue(watch.directory(root))
            self.assertFalse(watch.directory(root))
            descriptor = watch.descriptors[0]
            watch.close()
            with self.assertRaises(OSError):
                os.fstat(descriptor)


if __name__ == "__main__":
    unittest.main()
