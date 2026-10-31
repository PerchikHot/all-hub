"""Install real Veyrion icon artwork into generated Flutter Android/Windows projects.

Sources are cropped from the user's approved five-icon reference (no Material
glyphs). Run after 'flutter create', before building the app.
"""
from __future__ import annotations
import argparse
from pathlib import Path
from PIL import Image

ASSETS = Path(__file__).resolve().parents[1] / "assets" / "icons"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def build(project: str, root: Path) -> None:
    source = ASSETS / (project + ".webp")
    with Image.open(source) as original:
        icon = original.convert("RGBA")
    if icon.size != (192, 192):
        raise ValueError(f"Icon source {source} must be 192x192")
    android = root / "android" / "app" / "src" / "main" / "res"
    if android.exists():
        for density, pixels in DENSITIES.items():
            target = android / ("mipmap-" + density) / "ic_launcher.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target)
        foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
        foreground.alpha_composite(icon.resize((288, 288), Image.Resampling.LANCZOS), (72, 72))
        path = android / "drawable-nodpi" / "ic_launcher_foreground.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        foreground.save(path)
        xml = android / "mipmap-anydpi-v26" / "ic_launcher.xml"
        xml.parent.mkdir(parents=True, exist_ok=True)
        xml.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
            '<background android:drawable="@color/veyrion_icon_background"/>'
            '<foreground android:drawable="@drawable/ic_launcher_foreground"/>'
            '</adaptive-icon>\n', encoding="utf-8")
        color = android / "values" / "veyrion_icon_colors.xml"
        color.parent.mkdir(parents=True, exist_ok=True)
        color.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources><color name="veyrion_icon_background">#050A1A</color></resources>\n',
            encoding="utf-8")
    windows = root / "windows" / "runner" / "resources" / "app_icon.ico"
    if windows.parent.exists():
        windows.parent.mkdir(parents=True, exist_ok=True)
        icon.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS).save(
            windows, format="ICO", sizes=[(16, 16), (24, 24), (32, 32),
                                         (48, 48), (64, 64), (128, 128), (256, 256)])


def verify(project: str, root: Path) -> None:
    source = ASSETS / (project + ".webp")
    with Image.open(source) as im:
        assert im.size == (192, 192), f"Invalid icon source: {source}"
    android = root / "android" / "app" / "src" / "main" / "res"
    windows = root / "windows" / "runner" / "resources" / "app_icon.ico"
    if android.exists():
        for density, pixels in DENSITIES.items():
            with Image.open(android / ("mipmap-" + density) / "ic_launcher.png") as im:
                assert im.size == (pixels, pixels)
        with Image.open(android / "drawable-nodpi" / "ic_launcher_foreground.png") as im:
            assert im.size == (432, 432)
        assert (android / "mipmap-anydpi-v26" / "ic_launcher.xml").exists()
    if windows.parent.exists():
        with Image.open(windows) as im:
            assert (16, 16) in im.ico.sizes()
            assert (256, 256) in im.ico.sizes()
    assert android.exists() or windows.parent.exists(), "Run after flutter create"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", choices=["all_hub", "kopilka"], default="all_hub")
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if not args.verify:
        build(args.project, args.root)
    verify(args.project, args.root)
