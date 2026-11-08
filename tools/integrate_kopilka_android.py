#!/usr/bin/env python3
"""Integrate Kopilka into the All Hub APK without destroying the launcher channel."""
from pathlib import Path

root = Path("android/app/src/main/kotlin")
activities = list(root.rglob("MainActivity.kt"))
assert len(activities) == 1, "Expected one generated MainActivity"
target = activities[0]
package = ".".join(target.parent.relative_to(root).parts)
source = Path("kopilka/android")
kopilka = (source / "MainActivity.kt").read_text()
launcher = target.read_text()
assert "allhub/launcher" in launcher and "kopilka/notifications" in kopilka
assert "class MainActivity : FlutterActivity() {" in launcher
assert "class MainActivity : FlutterActivity() {" in kopilka
for path in source.glob("*.kt"):
    # Unit-test sources use JUnit and must never be compiled into the release APK.
    # The upstream Kopilka keeps some *Test.kt files alongside production sources.
    if path.name == "MainActivity.kt" or path.name.endswith("Test.kt"):
        continue
    data = path.read_text()
    assert data.startswith("package com.veyrion.kopilka_app"), path
    (target.parent / path.name).write_text(data.replace(
        "package com.veyrion.kopilka_app", "package " + package, 1))
helpers = kopilka.split("class MainActivity : FlutterActivity() {", 1)[1].split(
    "    override fun configureFlutterEngine(", 1)[0]
channel = kopilka.split(
    '        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kopilka/notifications")', 1)[1]
channel = channel.rsplit("\n    }\n}", 1)[0]
assert "override fun onResume()" in helpers and "setMethodCallHandler" in channel
imports = "\n".join(line for line in kopilka.splitlines()
                    if line.startswith("import ") and line not in launcher)
launcher = launcher.replace("class MainActivity : FlutterActivity() {",
    "class MainActivity : FlutterActivity() {\n" + helpers, 1)
launcher = launcher.replace("    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {",
    '    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n'
    '        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kopilka/notifications")'
    + channel + "\n", 1)
# Kotlin imports must precede annotations such as @Suppress.
if imports:
    lines = launcher.splitlines(keepends=True)
    last_import = max((i for i, line in enumerate(lines)
                       if line.startswith("import ")), default=-1)
    assert last_import >= 0, "Launcher must have imports"
    lines.insert(last_import + 1, imports + "\n")
    launcher = "".join(lines)
assert launcher.index("import ") < launcher.index("@Suppress")
assert launcher.count('"allhub/launcher"') == 1
assert launcher.count('"kopilka/notifications"') == 1
target.write_text(launcher)
manifest = Path("android/app/src/main/AndroidManifest.xml")
xml = manifest.read_text()
service = ('<service android:name=".BankNotificationService" '
           'android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" '
           'android:exported="true"><intent-filter><action '
           'android:name="android.service.notification.NotificationListenerService"/>'
           '</intent-filter></service>')
assert "</application>" in xml and "BankNotificationService" not in xml
manifest.write_text(xml.replace("</application>", service + "</application>", 1))
print("Both launcher and bank notification channels integrated")
