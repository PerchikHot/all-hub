# All Hub v0.1.0

Cross-platform Flutter project launcher for Android and Windows.

Features: project catalog, GitHub release checks, CI status, and links to downloads.

## Build

```bash
flutter create --platforms=android,windows --project-name all_hub .
flutter pub get
flutter run
```

GitHub Actions builds Android APK and Windows desktop bundles. The initial version does not yet install or update apps automatically.
