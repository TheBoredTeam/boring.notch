#!/usr/bin/env python3
"""Inject public licensing configuration into an app plist. No private signing key is accepted."""
import base64
import json
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse

def stamp(path, environ):
    names = ("EXTENSION_LICENSE_PUBLIC_KEYS", "EXTENSION_LICENSE_SERVER_URL")
    values = [environ.get(name, "").strip() for name in names]
    if not any(values):
        return  # Public/contributor builds remain independent of the private product.
    if not all(values):
        raise ValueError("Extension public keys and license server must be configured together")
    keys = json.loads(values[0])
    if not isinstance(keys, dict) or not keys:
        raise ValueError("Public keys must be a non-empty key-ID to base64 mapping")
    for key_id, value in keys.items():
        if not isinstance(key_id, str) or not key_id or not isinstance(value, str):
            raise ValueError("Invalid public key mapping")
        if len(base64.b64decode(value, validate=True)) != 32:
            raise ValueError("Only 32-byte Ed25519 public keys may be embedded")
    url = urlparse(values[1])
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.path not in ("", "/") or url.query or url.fragment:
        raise ValueError("The license server must be an HTTPS origin without credentials, paths, queries, or fragments")
    with path.open("rb") as source:
        info = plistlib.load(source)
    info["BNExtensionLicensePublicKeys"] = keys
    info["BNExtensionLicenseServerURL"] = values[1].rstrip("/")
    info["BNLockScreenLyricsCheckoutURL"] = values[1].rstrip("/") + "/buy?product=theboringteam.boringnotch.lockscreen-lyrics"
    with path.open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)


if __name__ == "__main__":
    stamp(Path(sys.argv[1]), os.environ)
