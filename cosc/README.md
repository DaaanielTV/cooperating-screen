# Cooperating Screen Flutter App

Flutter mobile client for Cooperating Screen.

## Overview

This app provides device onboarding, pairing flows, and UI entry points for WebRTC-powered screen sharing sessions.

## Setup

```bash
cd cosc
flutter pub get
flutter run
```

## Development

- Update Supabase values in `lib/main.dart` for local testing.
- Use `flutter analyze` and `flutter test` before opening pull requests.

## Build

```bash
flutter build apk
flutter build ios
```

## Troubleshooting

- If dependencies fail to resolve: run `flutter clean && flutter pub get`.
- If platform builds fail: verify Android Studio/Xcode setup and SDK paths.

## Related docs

See [../README.md](../README.md) for top-level project and deployment guidance.
