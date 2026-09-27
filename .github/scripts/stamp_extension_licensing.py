#!/usr/bin/env python3
"""Inject public licensing configuration into an app plist. No private signing key is accepted."""
import base64
import json
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse

DEFAULT_CHECKOUT_URL = "https://buymeacoffee.com/jfxh67wvfxq/e/580376"


def stamp(path, environ):
    names = ("EXTENSION_LICENSE_PUBLIC_KEYS", "EXTENSION_LICENSE_SERVER_URL", "EXTENSION_CHECKOUT_URL")
    values = [environ.get(name, "").strip() for name in names]
    if not any(values):
        return  # Public/contributor builds remain independent of the private product.
    values[2] = values[2] or DEFAULT_CHECKOUT_URL
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
    for value in values[1:]:
        url = urlparse(value)
        if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError("Licensing URLs must be HTTPS URLs without credentials, queries, or fragments")
    checkout = urlparse(values[2])
    if checkout.hostname not in ("buymeacoffee.com", "www.buymeacoffee.com"):
        raise ValueError("The checkout must point to Buy Me a Coffee")
    with path.open("rb") as source:
        info = plistlib.load(source)
    info["BNExtensionLicensePublicKeys"] = keys
    info["BNExtensionLicenseServerURL"] = values[1].rstrip("/")
    info["BNLockScreenLyricsCheckoutURL"] = values[2]
    with path.open("wb") as target:
        plistlib.dump(info, target, sort_keys=False)


if __name__ == "__main__":
    stamp(Path(sys.argv[1]), os.environ)
