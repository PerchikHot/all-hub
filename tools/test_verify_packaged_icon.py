"""Tests for APK icon inspection without Android SDK or device."""
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

from PIL import Image
from verify_packaged_icon import ASSETS, verify_apk


class PackagedIconTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / "app.apk"
        with Image.open(ASSETS / "all_hub.webp") as im:
            self.expected = im.convert("RGBA")

    def write_apk(self, image):
        data = BytesIO()
        image.save(data, format="PNG")
        with ZipFile(self.apk, "w") as archive:
            # AAPT2 may rename this path; do not rely on mipmap naming.
            archive.writestr("res/a1.png", data.getvalue())
            archive.writestr("lib/arm64-v8a/libllama.so", b"fake-lib" * 200)

    def test_renamed_resource_is_accepted_when_pixels_match(self):
        self.write_apk(self.expected)
        self.assertEqual(verify_apk(self.apk, "all_hub",
                         ("lib/arm64-v8a/libllama.so",)), "res/a1.png")

    def test_different_rgb_same_alpha_is_rejected(self):
        # RGBA ImageChops.getbbox() alone misses this exact regression.
        altered = self.expected.copy()
        altered.putpixel((0, 0), (0, 255, 0, self.expected.getpixel((0, 0))[3]))
        self.write_apk(altered)
        with self.assertRaisesRegex(ValueError, "artwork not found"):
            verify_apk(self.apk, "all_hub")

    def test_missing_native_library_fails(self):
        self.write_apk(self.expected)
        with self.assertRaisesRegex(ValueError, "Missing Android native"):
            verify_apk(self.apk, "all_hub", ("lib/arm64-v8a/missing.so",))


if __name__ == "__main__":
    unittest.main()
