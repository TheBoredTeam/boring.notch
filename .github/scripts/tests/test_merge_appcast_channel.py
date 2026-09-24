#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from merge_appcast_channel import SPARKLE_NS, merge_channel_item  # noqa: E402


ET.register_namespace("sparkle", SPARKLE_NS)
CHANNEL = f"{{{SPARKLE_NS}}}channel"
VERSION = f"{{{SPARKLE_NS}}}version"


def appcast(*items: str) -> str:
    return f"""<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="{SPARKLE_NS}" version="2.0">
    <channel>
        {''.join(items)}
    </channel>
</rss>
"""


def stable_item(version: str) -> str:
    return f"""<item>
            <title>{version}</title>
            <sparkle:version>{version}</sparkle:version>
        </item>
        """


def beta_item(version: str) -> str:
    return f"""<item>
            <title>{version}</title>
            <sparkle:channel>beta</sparkle:channel>
            <sparkle:version>{version}</sparkle:version>
        </item>
        """


class MergeAppcastChannelTests(unittest.TestCase):
    def write_appcast(self, directory: Path, name: str, contents: str) -> Path:
        path = directory / name
        path.write_text(contents, encoding="utf-8")
        return path

    def item_versions(self, path: Path) -> list[tuple[str | None, str | None]]:
        tree = ET.parse(path)
        items = tree.getroot().find("channel").findall("item")
        result: list[tuple[str | None, str | None]] = []
        for item in items:
            channel = item.find(CHANNEL)
            version = item.find(VERSION)
            result.append((
                channel.text if channel is not None else None,
                version.text if version is not None else None,
            ))
        return result

    def test_preserves_stable_items_and_prepends_generated_beta(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            existing = self.write_appcast(
                directory,
                "existing.xml",
                appcast(stable_item("271"), stable_item("262")),
            )
            generated = self.write_appcast(directory, "generated.xml", appcast(beta_item("300")))

            merge_channel_item(existing, generated, "beta")

            self.assertEqual(
                self.item_versions(existing),
                [("beta", "300"), (None, "271"), (None, "262")],
            )

    def test_replaces_existing_channel_items(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            existing = self.write_appcast(
                directory,
                "existing.xml",
                appcast(beta_item("280"), stable_item("271")),
            )
            generated = self.write_appcast(directory, "generated.xml", appcast(beta_item("300")))

            merge_channel_item(existing, generated, "beta")

            self.assertEqual(self.item_versions(existing), [("beta", "300"), (None, "271")])

    def test_fails_when_generated_appcast_has_no_requested_channel_item(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            existing = self.write_appcast(directory, "existing.xml", appcast(stable_item("271")))
            generated = self.write_appcast(directory, "generated.xml", appcast(stable_item("300")))

            with self.assertRaisesRegex(ValueError, "No 'beta' channel item"):
                merge_channel_item(existing, generated, "beta")


if __name__ == "__main__":
    unittest.main()
