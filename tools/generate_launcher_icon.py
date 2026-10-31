from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

n = 1024
im = Image.new("RGB", (n, n), "#101b36")
d = ImageDraw.Draw(im)
for k in range(12, 0, -1):
    pad = 60 + k * 10
    d.rounded_rectangle((pad,pad,n-pad,n-pad), radius=220, outline=(23,58,116), width=3)
d.rounded_rectangle((74,74,950,950), radius=218, outline="#3988f7", width=18)
d.polygon([(512,158),(740,279),(814,593),(708,801),(512,876),(316,801),(210,593),(284,279)],
          fill="#070d20", outline="#53c9ff", width=18)
d.polygon([(512,259),(660,340),(714,588),(624,742),(512,796),(400,742),(310,588),(364,340)],
          fill="#101b36")
d.polygon([(328,492),(476,526),(444,570),(346,555)], fill="#53c9ff")
d.polygon([(696,492),(548,526),(580,570),(678,555)], fill="#53c9ff")
for density, pixels in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
    folder = Path("android/app/src/main/res") / ("mipmap-" + density)
    folder.mkdir(parents=True, exist_ok=True)
    im.resize((pixels,pixels), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")
print("Android launcher icons generated")

# Windows desktop/taskbar executable icon; Flutter's default icon is replaced
# during CI after generating the Windows platform runner.
windows_icon = Path('windows/runner/resources/app_icon.ico')
if windows_icon.parent.exists():
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    im.save(windows_icon, format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
    print('Windows desktop/taskbar icon generated:', windows_icon)
