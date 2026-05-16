#!/usr/bin/env python3

from __future__ import annotations

import copy
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


def channel_element(tree: ET.ElementTree, path: Path) -> ET.Element:
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError(f"No channel element found in {path}")
    return channel


def first_item_index(channel: ET.Element) -> int:
    for index, child in enumerate(list(channel)):
        if child.tag == "item":
            return index
    return len(channel)


def merge_channel_item(existing_appcast: Path, generated_appcast: Path, channel_name: str) -> None:
    existing_tree = ET.parse(existing_appcast)
    generated_tree = ET.parse(generated_appcast)
    existing_channel = channel_element(existing_tree, existing_appcast)
    generated_channel = channel_element(generated_tree, generated_appcast)

    generated_items = [
        item for item in generated_channel.findall("item")
        if channel_for_item(item) == channel_name
    ]
    if not generated_items:
        raise ValueError(f"No {channel_name!r} channel item found in {generated_appcast}")

    for item in list(existing_channel.findall("item")):
        if channel_for_item(item) == channel_name:
            existing_channel.remove(item)

    existing_channel.insert(first_item_index(existing_channel), copy.deepcopy(generated_items[0]))
    ET.indent(existing_tree, space="    ")
    existing_tree.write(existing_appcast, encoding="utf-8", xml_declaration=True)


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 3:
        print(
            "Usage: merge_appcast_channel.py EXISTING_APPCAST GENERATED_APPCAST CHANNEL",
            file=sys.stderr,
        )
        return 1

    existing_appcast = Path(args[0])
    generated_appcast = Path(args[1])
    channel_name = args[2]

    try:
        merge_channel_item(existing_appcast, generated_appcast, channel_name)
    except Exception as error:
        print(f"Error merging {channel_name!r} appcast item: {error}", file=sys.stderr)
        return 2

    print(f"Merged {channel_name!r} appcast item into {existing_appcast}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
