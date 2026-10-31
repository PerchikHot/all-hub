"""Verify that the actual APK contains the approved Veyrion launcher artwork.

Android's AAPT2 resource compiler may rename PNG resources, so checking for
literal res/mipmap-xxxhdpi/ic_launcher.png paths inside the APK is incorrect.
Instead compare decoded resource pixels with the approved 192x192 source.
"""
from __future__ import annotations

import argparse
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile, BadZipFile

from PIL import Image, ImageChops

ASSETS = Path(__file__).resolve().parents[1] / "assets" / "icons"


def verify_apk(apk: Path, project: str, required_libs: tuple[str, ...] = ()) -> str:
    source = ASSETS / f"{project}.webp"
    with Image.open(source) as original:
        expected = original.convert("RGBA")
    if expected.size != (192, 192):
        raise ValueError("Approved source must be 192x192")
    if not apk.is_file() or apk.stat().st_size < 1024:
        raise ValueError("Missing or empty APK")
    with ZipFile(apk) as archive:
        names = set(archive.namelist())
        missing = [name for name in required_libs if name not in names]
        if missing:
            raise ValueError("Missing Android native libraries: " + ", ".join(missing))
        for name in sorted(names):
            # AAPT2 may flatten/minify resource names, but launcher bitmaps
            # remain decoded PNG resources. Never accept assets/flutter_assets.
            if not name.startswith("res/") or not name.lower().endswith(".png"):
                continue
            if archive.getinfo(name).file_size > 4 * 1024 * 1024:
                continue
            try:
                with Image.open(BytesIO(archive.read(name))) as image:
                    if image.size != expected.size:
                        continue
                    actual = image.convert("RGBA")
                    if ImageChops.difference(actual, expected).getbbox() is None:
                        return name
            except (OSError, ValueError):
                continue
    raise ValueError("Approved 192x192 launcher artwork not found in APK resources")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, choices=("all_hub", "kopilka"))
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--require-lib", action="append", default=[])
    args = parser.parse_args()
    print("Verified launcher artwork in", verify_apk(args.apk, args.project, tuple(args.require_lib)))
