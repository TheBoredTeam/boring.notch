import base64
import json
import plistlib
import tempfile
import unittest
from pathlib import Path

from stamp_extension_licensing import stamp


class LicensingBuildConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "Info.plist"
        self.path.write_bytes(plistlib.dumps({"CFBundleName": "Boring Notch"}))
        self.config = {
            "EXTENSION_LICENSE_PUBLIC_KEYS": json.dumps({"test": base64.b64encode(bytes(32)).decode()}),
            "EXTENSION_LICENSE_SERVER_URL": "https://licenses.example.com",
            "EXTENSION_CHECKOUT_URL": "https://buymeacoffee.com/jfxh67wvfxq/e/580376",
        }

    def test_normal_public_build_needs_no_configuration(self):
        before = self.path.read_bytes()
        stamp(self.path, {})
        self.assertEqual(before, self.path.read_bytes())

    def test_embeds_public_keys_without_replacing_existing_settings(self):
        stamp(self.path, self.config)
        info = plistlib.loads(self.path.read_bytes())
        self.assertEqual(info["CFBundleName"], "Boring Notch")
        self.assertIn("test", info["BNExtensionLicensePublicKeys"])

    def test_partial_configuration_fails_closed(self):
        with self.assertRaises(ValueError):
            stamp(self.path, {"EXTENSION_LICENSE_SERVER_URL": "https://example.com"})

    def test_shop_url_is_defaulted_for_configured_builds(self):
        del self.config["EXTENSION_CHECKOUT_URL"]
        stamp(self.path, self.config)
        info = plistlib.loads(self.path.read_bytes())
        self.assertEqual(info["BNLockScreenLyricsCheckoutURL"], "https://buymeacoffee.com/jfxh67wvfxq/e/580376")

    def test_private_key_sized_material_is_rejected(self):
        self.config["EXTENSION_LICENSE_PUBLIC_KEYS"] = json.dumps({"bad": base64.b64encode(bytes(64)).decode()})
        with self.assertRaises(ValueError):
            stamp(self.path, self.config)

    def test_insecure_or_wrong_checkout_is_rejected(self):
        for url in ["http://buymeacoffee.com/test", "https://other.example/test", "https://user:pass@buymeacoffee.com/test"]:
            self.config["EXTENSION_CHECKOUT_URL"] = url
            with self.assertRaises(ValueError):
                stamp(self.path, self.config)


if __name__ == "__main__":
    unittest.main()
