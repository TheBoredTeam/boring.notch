# SPDX-License-Identifier: GPL-3.0-only

"""Bounded JSON projection for length-prefixed Desktop IPC frames.

Conversation text is validated and discarded in bounded chunks while reading
the socket. Only activity and protocol metadata survive the projection.
"""

import codecs
import json
import re


CHUNK_BYTES = 64 * 1024
MAX_SCALAR_BYTES = 256
# Streaming recursion is capped; complete discarded chunks also use the C
# decoder's own depth guard and can never exceed CHUNK_BYTES of source text.
MAX_DEPTH = 128
SCALAR = object()
VISIBILITY_SCALAR = object()
PATCH_VALUE = object()
PATCHES = object()
STATUS = {"type": SCALAR, "activeFlags": (SCALAR, 16)}
VISIBILITY_FIELDS = ("source", "threadSource", "parentThreadId", "ephemeral", "sideConversation")
PATCH_PATH = (SCALAR, 3)
PATCH = {"op": SCALAR, "path": PATCH_PATH, "value": PATCH_VALUE}
MESSAGE = {
    "type": SCALAR, "method": SCALAR, "version": SCALAR,
    "sourceClientId": SCALAR, "requestId": SCALAR,
    "result": {"clientId": SCALAR},
    "params": {
        "hostId": SCALAR, "conversationId": SCALAR,
        "clientId": SCALAR, "status": SCALAR,
        "change": {
            "type": SCALAR, "revision": SCALAR, "baseRevision": SCALAR,
            "conversationState": {"threadRuntimeStatus": STATUS,
                                  **{key: VISIBILITY_SCALAR for key in VISIBILITY_FIELDS}},
            "patches": PATCHES,
        },
    },
}
STRING_RUN = re.compile(rb'(?:[^"\\\x00-\x1f]+|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})+')
WHITESPACE = re.compile(rb'[ \t\r\n]*')
SCALAR_END = re.compile(rb'[ \t\r\n,\]}]')


class ActivityJSONReader:
    """Read exactly one frame; the callback must return at most its requested bytes."""

    def __init__(self, read, size):
        self.read = read
        self.remaining = size
        self.buffer = b""
        self.position = 0
        self.text_buffer = None
        self.utf8 = codecs.getincrementaldecoder("utf-8")()

    def _available(self):
        if self.position < len(self.buffer):
            return True
        if not self.remaining:
            return False
        chunk = self.read(min(CHUNK_BYTES, self.remaining))
        if not chunk or len(chunk) > min(CHUNK_BYTES, self.remaining):
            raise ValueError("Incomplete IPC JSON frame")
        self.remaining -= len(chunk)
        # Validate UTF-8 one chunk at a time without retaining decoded text.
        self.utf8.decode(chunk, final=self.remaining == 0)
        self.buffer = chunk
        self.position = 0
        self.text_buffer = None
        return True

    def _peek(self):
        return self.buffer[self.position] if self._available() else None

    def _take(self):
        value = self._peek()
        if value is None:
            raise ValueError("Incomplete IPC JSON value")
        self.position += 1
        return value

    def _space(self):
        while self._available():
            self.position = WHITESPACE.match(self.buffer, self.position).end()
            if self.position < len(self.buffer):
                return

    def _string(self, keep):
        if self._take() != 34:
            raise ValueError("Expected IPC JSON string")
        captured = bytearray(b'"') if keep else None
        while self._available():
            match = STRING_RUN.match(self.buffer, self.position)
            end = match.end() if match else self.position
            if captured is not None:
                if len(captured) + end - self.position > MAX_SCALAR_BYTES:
                    captured = None
                else:
                    captured.extend(self.buffer[self.position:end])
            self.position = end
            if self.position == len(self.buffer):
                continue
            special = self._take()
            if special == 34:
                if captured is None:
                    return None
                captured.append(34)
                return json.loads(captured)
            if special != 92:
                raise ValueError("Control character in IPC JSON string")
            escaped = self._take()
            suffix = bytearray([92, escaped])
            if escaped == 117:
                for _ in range(4):
                    digit = self._take()
                    if digit not in b"0123456789abcdefABCDEF":
                        raise ValueError("Invalid IPC JSON Unicode escape")
                    suffix.append(digit)
            elif escaped not in b'"\\/bfnrt':
                raise ValueError("Invalid IPC JSON escape")
            if captured is not None:
                captured.extend(suffix)
                if len(captured) > MAX_SCALAR_BYTES:
                    captured = None
        raise ValueError("Unterminated IPC JSON string")

    def _scalar(self, keep):
        token = bytearray()
        while self._available():
            match = SCALAR_END.search(self.buffer, self.position)
            end = match.start() if match else len(self.buffer)
            if len(token) + end - self.position > MAX_SCALAR_BYTES:
                raise ValueError("Oversized IPC JSON scalar")
            token.extend(self.buffer[self.position:end])
            self.position = end
            if match:
                break
        try:
            value = json.loads(token)
        except (ValueError, UnicodeError):
            raise ValueError("Invalid IPC JSON scalar") from None
        if isinstance(value, (dict, list, str)):
            raise ValueError("Invalid IPC JSON scalar")
        return value if keep else None

    def _value(self, schema, depth=0):
        if depth > MAX_DEPTH:
            raise ValueError("IPC JSON nesting exceeds limit")
        self._space()
        first = self._peek()
        if schema is VISIBILITY_SCALAR:
            if first in (123, 91):
                self._value(None, depth)
                # Preserve invalid shape without retaining its contents or
                # confusing a malformed parent/source with an absent value.
                return []
            if first == 34:
                value = self._string(True)
                return [] if value is None else value
            schema = SCALAR
        if schema is None and self._skip_native():
            return None
        if schema is PATCH_VALUE:
            schema = STATUS if first == 123 else ((SCALAR, 16) if first == 91 else SCALAR)
        if first == 34:
            return self._string(schema is SCALAR)
        if first == 123:
            return self._object(schema if isinstance(schema, dict) else None, depth + 1)
        if first == 91:
            return self._array(schema, depth + 1)
        return self._scalar(schema is SCALAR)

    def _skip_native(self):
        """Discard a complete small value using CPython's C decoder, within one chunk."""
        if self.text_buffer is None:
            # Latin-1 keeps byte offsets exact. UTF-8 was validated on input; these
            # temporary values are discarded, never used as projected metadata.
            self.text_buffer = self.buffer.decode("latin-1")
        try:
            _, end = json.JSONDecoder().raw_decode(self.text_buffer, self.position)
        except (ValueError, RecursionError):
            return False
        if end == len(self.buffer) and self.remaining:
            return False
        if end < len(self.buffer) and self.buffer[end] not in b" \t\r\n,}]":
            return False
        self.position = end
        return True

    def _skip_array_batch(self):
        """Validate/discard several array values in C, without collecting the array."""
        end = self.buffer.rfind(b",", self.position)
        for _ in range(8):
            if end <= self.position:
                return False
            try:
                json.loads(b"[" + self.buffer[self.position:end] + b"]")
            except (ValueError, RecursionError):
                end = self.buffer.rfind(b",", self.position, end)
                continue
            self.position = end + 1
            return True
        return False

    def _object(self, schema, depth):
        self._take()
        result = {} if schema is not None else None
        self._space()
        if self._peek() == 125:
            self._take()
            return result
        while True:
            self._space()
            key = self._string(schema is not None)
            self._space()
            if self._take() != 58:
                raise ValueError("Expected IPC JSON colon")
            child = schema.get(key) if schema is not None else None
            value = self._value(child, depth)
            if child is not None:
                result[key] = value
            self._space()
            separator = self._take()
            if separator == 125:
                return result
            if separator != 44:
                raise ValueError("Expected IPC JSON object separator")

    def _array(self, schema, depth):
        self._take()
        child = PATCH if schema is PATCHES else (schema[0] if isinstance(schema, tuple) else None)
        limit = 128 if schema is PATCHES else (schema[1] if isinstance(schema, tuple) else 0)
        result = [] if child is not None else None
        self._space()
        if self._peek() == 93:
            self._take()
            return result
        while True:
            if child is None:
                self._space()
                if self._skip_array_batch():
                    continue
            value = self._value(child, depth)
            retain = child is not None
            if schema is PATCHES:
                if not isinstance(value, dict):
                    raise ValueError("Expected IPC status patch object")
                path = value.get("path") if isinstance(value, dict) else None
                retain = (isinstance(path, list) and bool(path)
                          and path[0] in ("threadRuntimeStatus", *VISIBILITY_FIELDS))
            if retain:
                if len(result) >= limit:
                    if schema is PATCHES:
                        raise ValueError("Too many IPC status patches")
                    # Content patches can contain huge arrays; they are not a playlist.
                    if schema is not PATCH_PATH:
                        result = None
                    child = None
                else:
                    result.append(value)
            self._space()
            separator = self._take()
            if separator == 93:
                return result
            if separator != 44:
                raise ValueError("Expected IPC JSON array separator")

    def decode(self):
        result = self._value(MESSAGE)
        self._space()
        if self._peek() is not None or not isinstance(result, dict):
            raise ValueError("Expected one IPC JSON object")
        return result
