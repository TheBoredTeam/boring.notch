# SPDX-License-Identifier: GPL-3.0-only

"""Read-only projection of Codex Desktop's private IPC runtime status.

The Unix socket remains private to this user. The loopback endpoint publishes
only an aggregate phase, count and freshness timestamp. Conversation snapshots
are discarded immediately after extracting runtime status; no text is logged.
"""

import http.server
import json
import os
from pathlib import Path
import select
import socket
import stat
import struct
import subprocess
import threading
import time
import uuid

from codex_activity_json import ActivityJSONReader, VISIBILITY_FIELDS
from codex_activity_discovery import DesktopServerDiscovery, ThreadDiscovery, THREAD_ID


PORT = 48731
CODEX_STATE_ROOT = Path.home() / ".codex"
SOCKET_PATH = CODEX_STATE_ROOT / "ipc" / "ipc.sock"
STREAM_VERSION = 11
MAX_FRAME_BYTES = 256 * 1024 * 1024
STATUS_TYPES = {"active", "idle", "notLoaded", "systemError"}
WAIT_FLAGS = {"waitingOnApproval", "waitingOnUserInput"}


def clean_status(value):
    if (not isinstance(value, dict) or not isinstance(value.get("type"), str)
            or value["type"] not in STATUS_TYPES):
        return None
    status_type = value["type"]
    flags = value.get("activeFlags", [])
    if not isinstance(flags, list) or any(not isinstance(flag, str) or flag not in WAIT_FLAGS for flag in flags):
        return None
    return {"type": status_type, "activeFlags": list(flags)}


def visible_task(state):
    """Classify Desktop task metadata; None means it cannot yet be verified."""
    if not isinstance(state, dict):
        return None
    if (state.get("parentThreadId") is not None
            or state.get("threadSource") in ("subagent", "guardian_review", "pull_request_fix_automation")
            or state.get("ephemeral") is True or state.get("sideConversation") is True):
        return False
    # Count the task, not its backstage crew. Unverified sources stay uncounted.
    if (state.get("source") not in ("vscode", "cli", "exec")
            or not isinstance(state.get("threadSource"), (str, type(None)))
            or any(state.get(key, False) is not False for key in ("ephemeral", "sideConversation"))):
        return None
    return True


class ActivityProjection:
    """Retains metadata only; every unknown state freezes the avatar."""

    def __init__(self):
        self.connected = False
        self.threads = {}
        self.archived = set()

    def disconnect(self):
        self.connected = False
        self.threads.clear()
        self.archived.clear()

    def consume(self, message, now):
        """Return a thread id when a revision gap needs a fresh snapshot."""
        if message.get("type") != "broadcast":
            return None
        method = message.get("method")
        params = message.get("params")
        if not isinstance(params, dict):
            return None
        if method == "client-status-changed" and params.get("status") == "disconnected":
            owner = params.get("clientId")
            self.threads = {key: state for key, state in self.threads.items()
                            if state["owner"] != owner}
            return None
        if method == "ipc-connection-reset":
            self.disconnect()
            return None
        if method in ("thread-archived", "thread-unarchived") and params.get("hostId") == "local":
            thread_id = params.get("conversationId")
            if isinstance(thread_id, str):
                self.threads.pop(thread_id, None)
                if method == "thread-archived":
                    self.archived.add(thread_id)
                else:
                    self.archived.discard(thread_id)
                    return thread_id
            return None
        if method != "thread-stream-state-changed" or params.get("hostId") != "local":
            return None
        thread_id = params.get("conversationId")
        if not isinstance(thread_id, str) or thread_id in self.archived:
            return None
        if message.get("version") != STREAM_VERSION:
            self.threads.pop(thread_id, None)
            return None
        change = params.get("change")
        if not isinstance(change, dict):
            self.threads.pop(thread_id, None)
            return None
        owner = message.get("sourceClientId")
        revision = change.get("revision")
        if not isinstance(revision, int) or not isinstance(owner, str):
            self.threads.pop(thread_id, None)
            return None
        if change.get("type") == "snapshot":
            state = change.get("conversationState")
            status = clean_status(state.get("threadRuntimeStatus")) if isinstance(state, dict) else None
            visible = visible_task(state)
            if status is None or visible is None:
                self.threads.pop(thread_id, None)
            else:
                self.threads[thread_id] = {"status": status, "revision": revision,
                                           "owner": owner, "seen": now, "visible": visible}
            return None
        if change.get("type") != "patches":
            return None
        current = self.threads.get(thread_id)
        if current is None or current["owner"] != owner or current["revision"] != change.get("baseRevision"):
            self.threads.pop(thread_id, None)
            return thread_id
        status = dict(current["status"])
        patches = change.get("patches")
        if not isinstance(patches, list):
            self.threads.pop(thread_id, None)
            return thread_id
        for patch in patches:
            if not isinstance(patch, dict):
                self.threads.pop(thread_id, None)
                return thread_id
            path = patch.get("path", [])
            if isinstance(path, list) and path and path[0] in VISIBILITY_FIELDS:
                # Reclassify from a complete snapshot before counting again.
                self.threads.pop(thread_id, None)
                return thread_id
            if not isinstance(path, list) or not path or path[0] != "threadRuntimeStatus":
                continue
            if len(path) == 1:
                status = clean_status(patch.get("value"))
            elif len(path) == 2 and path[1] in ("type", "activeFlags") and status is not None:
                status[path[1]] = patch.get("value")
            else:
                self.threads.pop(thread_id, None)
                return thread_id
        status = clean_status(status)
        if status is None:
            self.threads.pop(thread_id, None)
            return thread_id
        current.update(status=status, revision=revision, seen=now)
        return None

    def summary(self, now):
        visible = [state for state in self.threads.values() if state["visible"]]
        fresh = [state["status"] for state in visible
                 if state["status"]["type"] != "active" or now - state["seen"] <= 45]
        active = [state for state in fresh if state["type"] == "active"]
        working = [state for state in active if not state["activeFlags"]]
        if not self.connected or (visible and not fresh) or not self.threads:
            phase = "offline"
        elif working:
            phase = "active"
        elif active:
            phase = "waiting"
        elif any(state["type"] == "systemError" for state in fresh):
            phase = "error"
        else:
            phase = "idle"
        return {"service": "boringnotch-codex-activity", "version": 1,
                "phase": phase, "activeCount": len(active), "updatedAt": now}


class DesktopObserver:
    def __init__(self):
        self.projection = ActivityProjection()
        self.lock = threading.Lock()
        self.last_poll = 0
        self.sock = None
        self.client_id = None
        self.subscribed = {}
        self.probed_versions = {}
        self.next_probe = {}
        self.candidates = {}
        self.server_discovery = DesktopServerDiscovery()
        self.thread_discovery = ThreadDiscovery(CODEX_STATE_ROOT / "sessions")

    def snapshot(self):
        with self.lock:
            now = time.time()
            if now - self.last_poll > 8:
                return {"service": "boringnotch-codex-activity", "version": 1,
                        "phase": "offline", "activeCount": 0, "updatedAt": now}
            return self.projection.summary(now)

    def send(self, message):
        data = json.dumps(message, separators=(",", ":")).encode()
        self.sock.sendall(struct.pack("<I", len(data)) + data)

    def follow(self, thread_id, now):
        with self.lock:
            previous = self.projection.threads.get(thread_id)
            if thread_id in self.projection.archived or (previous and not previous["visible"]):
                return
            if previous is not None and previous["status"]["type"] != "active":
                self.projection.threads.pop(thread_id)
        self.send({"type": "broadcast", "sourceClientId": self.client_id,
                   "method": "thread-stream-following-changed", "version": 1,
                   "params": {"hostId": "local", "conversationId": thread_id, "following": True}})
        self.subscribed[thread_id] = now

    def unfollow(self, thread_id):
        if thread_id in self.subscribed:
            self.send({"type": "broadcast", "sourceClientId": self.client_id,
                       "method": "thread-stream-following-changed", "version": 1,
                       "params": {"hostId": "local", "conversationId": thread_id, "following": False}})
            self.subscribed.pop(thread_id, None)

    def refresh_subscriptions(self, candidates, now):
        self.candidates = candidates
        with self.lock:
            states = {key: dict(state) for key, state in self.projection.threads.items()}
        known = candidates.keys() | self.subscribed.keys() | self.next_probe.keys()
        for thread_id in sorted(known, key=lambda key: candidates.get(key, 0), reverse=True):
            modified = candidates.get(thread_id)
            state = states.get(thread_id)
            if thread_id in self.projection.archived or (state and not state["visible"]):
                self.unfollow(thread_id)
                continue
            last_sent = self.subscribed.get(thread_id)
            if last_sent is not None:
                if state and state["status"]["type"] == "active":
                    if now - max(last_sent, state["seen"]) >= 30:
                        self.follow(thread_id, now)
                # Verified idle tasks stay attached: a new turn need not write
                # its rollout before its active status arrives on this stream.
                elif state is None and now - last_sent >= 8:
                    self.unfollow(thread_id)
                    self.next_probe[thread_id] = now + 30
                continue
            changed = self.probed_versions.get(thread_id) != modified
            retry_unknown = state is None and now >= self.next_probe.get(thread_id, 0)
            if changed or retry_unknown:
                # Keep the fingerprint that triggered this probe; a racing write
                # must still be noticed after its snapshot arrives.
                self.probed_versions[thread_id] = modified
                self.follow(thread_id, now)

    def connect(self):
        entry = SOCKET_PATH.lstat()
        directory = SOCKET_PATH.parent.stat()
        if not stat.S_ISSOCK(entry.st_mode) or entry.st_uid != os.getuid() or directory.st_uid != os.getuid() or directory.st_mode & 0o022:
            raise OSError("Unsafe IPC ownership")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(2)
        self.sock.connect(str(SOCKET_PATH))
        self.send({"type": "request", "requestId": str(uuid.uuid4()), "method": "initialize",
                   "version": 0, "params": {"clientType": "boringNotch-activity-observer"}})

    def receive(self, now):
        if not select.select([self.sock], [], [], 0.2)[0]:
            return
        header = bytearray()
        while len(header) < 4:
            chunk = self.sock.recv(4 - len(header))
            if not chunk:
                raise EOFError()
            header.extend(chunk)
        size = struct.unpack("<I", header)[0]
        if size == 0 or size > MAX_FRAME_BYTES:
            raise ValueError("Invalid IPC frame length")
        message = ActivityJSONReader(self.sock.recv, size).decode()
        if message.get("type") == "response" and message.get("method") == "initialize":
            result = message.get("result")
            self.client_id = result.get("clientId") if isinstance(result, dict) else None
            with self.lock:
                self.projection.connected = isinstance(self.client_id, str) and bool(self.client_id)
        elif message.get("type") == "client-discovery-request":
            self.send({"type": "client-discovery-response", "requestId": message.get("requestId"),
                       "response": {"canHandle": False}})
        else:
            if message.get("method") == "ipc-connection-reset":
                raise ConnectionResetError()
            if message.get("method") == "client-status-changed":
                # New owners must get a fresh subscription after a window reconnects.
                self.subscribed.clear()
                self.probed_versions.clear()
                self.next_probe.clear()
            if message.get("method") == "thread-stream-following-status-requested":
                params = message.get("params")
                if (isinstance(params, dict) and params.get("hostId") == "local"
                        and isinstance(params.get("conversationId"), str)
                        and params["conversationId"] not in self.subscribed):
                    thread_id = params["conversationId"]
                    self.probed_versions[thread_id] = self.candidates.get(thread_id)
                    self.follow(thread_id, now)
            with self.lock:
                retry = self.projection.consume(message, now)
            if message.get("method") == "thread-archived":
                params = message.get("params") or {}
                if params.get("hostId") == "local":
                    self.unfollow(params.get("conversationId"))
            if retry:
                self.follow(retry, now)

    def reset(self):
        if self.sock:
            self.sock.close()
        self.sock = None
        self.client_id = None
        self.subscribed.clear()
        self.probed_versions.clear()
        self.next_probe.clear()
        self.candidates.clear()
        with self.lock:
            self.projection.disconnect()

    def run(self):
        identity = None
        checked_at = 0
        discovered_at = 0
        last_status = None
        last_error = None
        while True:
            try:
                now = time.time()
                if now - checked_at >= 2:
                    current = self.server_discovery.identity()
                    checked_at = now
                    if current != identity:
                        self.reset()
                        identity = current
                        discovered_at = 0
                        self.thread_discovery.close()
                with self.lock:
                    self.last_poll = now
                if identity is None:
                    time.sleep(1)
                    continue
                if self.sock is None:
                    self.connect()
                self.receive(now)
                status = self.snapshot()
                display_status = (status["phase"], status["activeCount"])
                if display_status != last_status:
                    print(f"Codex activity: {display_status[0]}, active tasks: {display_status[1]}", flush=True)
                    last_status = display_status
                last_error = None
                if self.client_id and now - discovered_at >= 2:
                    discovered_at = now
                    self.refresh_subscriptions(self.thread_discovery.candidates(identity[1]), now)
            except (OSError, ValueError, EOFError, subprocess.SubprocessError) as error:
                self.reset()
                self.server_discovery.invalidate()
                error_type = type(error).__name__
                if error_type != last_error:
                    print(f"Codex activity source disconnected ({error_type}); retrying", flush=True)
                    last_error = error_type
                time.sleep(2)


def main():
    observer = DesktopObserver()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/activity" or self.headers.get("Origin") or self.headers.get("Host") != f"127.0.0.1:{PORT}":
                self.send_error(404)
                return
            data = json.dumps(observer.snapshot(), separators=(",", ":")).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=observer.run, name="codex-desktop-observer", daemon=True).start()
    print(f"Codex Desktop activity projection listening on 127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    finally:
        observer.reset()
        observer.server_discovery.close()
        observer.thread_discovery.close()
        server.server_close()


if __name__ == "__main__":
    main()
