# SPDX-License-Identifier: GPL-3.0-only

"""Read-only process and filename discovery for the local activity bridge.

Directory notifications identify structural changes; cached file mtimes still
cover resumed tasks in old directories. No session contents are opened.
"""

import datetime
import os
import re
import resource
import select
import stat
import subprocess
import time


UUID_PATTERN = r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}"
# Segmented rollouts append another UUID; the task keeps the first one.
THREAD_ID = re.compile(
    rf"^rollout-\d{{4}}-\d{{2}}-\d{{2}}T\d{{2}}-\d{{2}}-\d{{2}}-({UUID_PATTERN})"
    rf"(?:_{UUID_PATTERN})?\.jsonl$")


class _KqueueWatch:
    """Bounded directory descriptors; process watches need no open process fd."""

    def __init__(self):
        try:
            self.queue = select.kqueue() if hasattr(select, "kqueue") else None
        except OSError:
            self.queue = None
        self.descriptors = []
        soft_limit = resource.getrlimit(resource.RLIMIT_NOFILE)[0]
        self.directory_limit = 512 if soft_limit == resource.RLIM_INFINITY else min(512, max(0, soft_limit - 64))

    def process(self, pid):
        if self.queue is None:
            return False
        event = select.kevent(pid, filter=select.KQ_FILTER_PROC,
                              flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                              fflags=select.KQ_NOTE_EXIT | select.KQ_NOTE_EXEC)
        try:
            self.queue.control([event], 0, 0)
            return True
        except OSError:
            return False

    def directory(self, path):
        if self.queue is None or len(self.descriptors) >= self.directory_limit:
            return False
        descriptor = None
        try:
            descriptor = os.open(path, getattr(os, "O_EVTONLY", os.O_RDONLY) | os.O_CLOEXEC)
            event = select.kevent(descriptor, filter=select.KQ_FILTER_VNODE,
                                  flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                  fflags=select.KQ_NOTE_WRITE | select.KQ_NOTE_RENAME
                                  | select.KQ_NOTE_DELETE | select.KQ_NOTE_REVOKE)
            self.queue.control([event], 0, 0)
            self.descriptors.append(descriptor)
            return True
        except OSError:
            if descriptor is not None:
                os.close(descriptor)
            return False

    def changed(self):
        if self.queue is None:
            return False
        try:
            return bool(self.queue.control(None, max(2, len(self.descriptors)), 0))
        except OSError:
            # Lost notification state must trigger reconciliation, never a stale cache.
            return True

    def close(self):
        if self.queue is not None:
            self.queue.close()
            self.queue = None
        for descriptor in self.descriptors:
            os.close(descriptor)
        self.descriptors.clear()


def _read_processes(pids=None):
    arguments = ["/bin/ps", "-axo", "pid=,ppid=,lstart=,comm="]
    if pids is not None:
        arguments = ["/bin/ps", "-p", ",".join(map(str, pids)), "-o", "pid=,ppid=,lstart=,comm="]
    result = subprocess.run(arguments, capture_output=True, text=True,
                            env={**os.environ, "LC_ALL": "C"}, timeout=3, check=False)
    if result.returncode not in (0, 1):
        result.check_returncode()
    processes = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 7)
        if len(fields) == 8:
            processes[int(fields[0])] = (int(fields[1]), " ".join(fields[2:7]), fields[7])
    return processes


def _server_record(processes, pid):
    server = processes.get(pid)
    if server is None:
        return None
    parent_pid, started, command = server
    parent = processes.get(parent_pid)
    if parent is None or not command.endswith(".app/Contents/Resources/codex"):
        return None
    if not parent[2].endswith(".app/Contents/MacOS/ChatGPT"):
        return None
    timestamp = datetime.datetime.strptime(started, "%a %b %d %H:%M:%S %Y").timestamp()
    return pid, timestamp, parent_pid, started, command, parent[1], parent[2]


class DesktopServerDiscovery:
    """Cache a verified Desktop-owned server, with immediate lifecycle invalidation.

    identity() returns (server pid, start timestamp, generation). The generation
    forces an observer reset after exec even if pid and start seconds are equal.
    Call at the bridge's normal two-second maintenance cadence; invalidate() on
    IPC failure and close() when the observer stops.
    """

    def __init__(self, reader=_read_processes, clock=time.monotonic, watch_factory=_KqueueWatch):
        self.reader = reader
        self.clock = clock
        self.watch_factory = watch_factory
        self.record = None
        self.watch = None
        self.generation = 0
        self.next_check = 0
        self.next_discovery = 0
        self.watched = False

    def invalidate(self):
        if self.watch is not None:
            self.watch.close()
        self.watch = None
        self.record = None
        self.next_discovery = 0

    def close(self):
        self.invalidate()

    def identity(self):
        now = self.clock()
        if self.record is not None:
            if self.watch.changed():
                self.invalidate()
            elif now >= self.next_check:
                current = _server_record(self.reader((self.record[0], self.record[2])), self.record[0])
                self.next_check = now + (60 if self.watched else 2)
                if current != self.record:
                    self.invalidate()
        if self.record is None and now >= self.next_discovery:
            self.next_discovery = now + 2
            processes = self.reader()
            candidate = next((record for pid in processes if (record := _server_record(processes, pid)) is not None), None)
            if candidate is not None:
                watch = self.watch_factory()
                try:
                    server_watched = watch.process(candidate[0])
                    parent_watched = watch.process(candidate[2])
                    current = _server_record(self.reader((candidate[0], candidate[2])), candidate[0])
                except Exception:
                    watch.close()
                    raise
                if current != candidate or watch.changed():
                    watch.close()
                    return None
                self.record = candidate
                self.watch = watch
                self.watched = server_watched and parent_watched
                self.next_check = now + (60 if self.watched else 2)
                self.generation += 1
        if self.record is None:
            return None
        return self.record[0], self.record[1], self.generation


class ThreadDiscovery:
    """Discover new and resumed tasks without repeatedly traversing the archive.

    Call candidates() at the bridge's discovery cadence. Cached file
    paths are stat'ed every call, including old rollouts. Directory watches are
    registered before enumeration; incomplete watches fall back to a full scan
    at that same cadence. A periodic scan reconciles quiet notification state.
    """

    def __init__(self, root, clock=time.monotonic, watch_factory=_KqueueWatch):
        self.root = os.fspath(root)
        self.clock = clock
        self.watch_factory = watch_factory
        self.watch = None
        self.files = {}
        self.signature = None
        self.next_scan = 0
        self.watched = False

    def close(self):
        if self.watch is not None:
            self.watch.close()
        self.watch = None
        self.files.clear()
        self.signature = None

    def _root_signature(self):
        try:
            entry = os.stat(self.root, follow_symlinks=False)
            return (entry.st_dev, entry.st_ino) if stat.S_ISDIR(entry.st_mode) else None
        except OSError:
            return None

    def _scan(self, signature, now):
        self.close()
        self.watch = self.watch_factory()
        self.watched = True
        self.signature = signature
        self.next_scan = now + 60
        directories = [self.root]
        while directories:
            directory = directories.pop()
            if not self.watch.directory(directory):
                self.watched = False
            try:
                with os.scandir(directory) as entries:
                    for entry in entries:
                        if entry.is_dir(follow_symlinks=False):
                            directories.append(entry.path)
                        elif entry.name.startswith("rollout-") and (match := THREAD_ID.search(entry.name)):
                            if entry.is_file(follow_symlinks=False):
                                self.files[entry.path] = match.group(1)
            except OSError:
                self.watched = False

    def candidates(self, started_at):
        signature = self._root_signature()
        if signature is None:
            self.close()
            return {}
        now = self.clock()
        if (signature != self.signature or not self.watched or now >= self.next_scan
                or self.watch.changed()):
            self._scan(signature, now)
        result = {}
        for path, thread_id in self.files.items():
            try:
                modified = os.stat(path, follow_symlinks=False).st_mtime
                if modified >= started_at:
                    result[thread_id] = max(modified, result.get(thread_id, modified))
            except OSError:
                # Retry transient failures next poll; structural scans prune deleted paths.
                pass
        return result
