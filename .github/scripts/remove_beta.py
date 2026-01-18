#!/usr/bin/env python3
"""
Remove the last beta item from an appcast XML file.
Usage: remove_beta.py path/to/appcast.xml

This script mirrors the inline Python used previously in the workflow.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def remove_last_beta_item(appcast_path: Path) -> int:
    if not appcast_path.exists():
        print(f"Appcast file not found: {appcast_path}")
        return 1

    try:
        tree = ET.parse(appcast_path)
        root = tree.getroot()

        channel = root.find('channel')
        if channel is None:
            print('No channel found in appcast')
            return 0

        items = channel.findall('item')
        removed = False
        for item in reversed(items):
            enclosure = item.find('enclosure')
            if enclosure is not None:
                version = enclosure.get('sparkle:version', '')
                if 'beta' in version.lower():
                    channel.remove(item)
                    removed = True
                    break

        if removed:
            tree.write(appcast_path, encoding='utf-8', xml_declaration=True)
            print('Removed beta item from appcast')
        else:
            print('No beta item found in appcast')

        return 0

    except Exception as e:
        print(f'Error processing appcast: {e}')
        return 2


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: remove_beta.py path/to/appcast.xml')
        sys.exit(1)

    path = Path(sys.argv[1])
    sys.exit(remove_last_beta_item(path))
