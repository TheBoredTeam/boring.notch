#!/usr/bin/env python3
"""Keep only one item for a channel in a Sparkle appcast.

The rolling nightly release reuses one DMG URL, so the dev appcast must hold
exactly one item: the freshly generated one. This script removes every other
item from the freshly generated appcast (any stale `dev` item plus items from
other channels, e.g. a legacy unchannelled entry) and fails if the requested
item is missing, so a broken generate_appcast output can never silently wipe
the channel without a replacement.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE_CHANNEL = f"{{{SPARKLE_NS}}}channel"


ET.register_namespace("sparkle", SPARKLE_NS)


def channel_for_item(item: ET.Element) -> str | None:
    channel = item.find(SPARKLE_CHANNEL)
    if channel is None or channel.text is None:
        return None
    return channel.text.strip() or None


def prune_channel(appcast: Path, channel_name: str) -> bool:
    """Keep only the item for channel_name; returns True when changed."""
    tree = ET.parse(appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError(f"No channel element found in {appcast}")

    items = channel.findall("item")
    keep = [
        item
        for item in items
        if channel_for_item(item) == channel_name
    ]
    if not keep:
        raise ValueError(f"No {channel_name!r} channel item found in {appcast}")
    if len(keep) > 1:
        raise ValueError(f"Multiple {channel_name!r} channel items found in {appcast}")

    removed = 0
    for item in items:
        if item not in keep:
            channel.remove(item)
            removed += 1

    if removed:
        ET.indent(tree, space="    ")
        tree.write(appcast, encoding="utf-8", xml_declaration=True)
    return removed > 0


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) < 1:
        print(
            "Usage: prune_appcast_channel.py APPCAST CHANNEL",
            file=sys.stderr,
        )
        return 1

    appcast = Path(args[0])
    channel_name = args[1] if len(args) > 1 else "dev"
    try:
        changed = prune_channel(appcast, channel_name)
    except Exception as error:
        print(f"Error pruning {channel_name!r} appcast item: {error}", file=sys.stderr)
        return 2

    if changed:
        print(f"Pruned appcast to the {channel_name!r} item only")
    else:
        print(f"Appcast already holds only the {channel_name!r} item")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
