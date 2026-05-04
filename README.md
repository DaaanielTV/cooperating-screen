## Warranty & Liability
This software is provided "as is", without warranty of any kind. See the LICENSE file for the full GPL-3.0 disclaimer of warranty and limitation of liability.

I'm not responsible if this breaks your setup. Test it before using it in production.

# Cooperating Screen

Cooperating Screen is an open-source cross-device screen sharing project built with Flutter, WebRTC, and a Node.js signaling service.

## Project Overview

This repository contains:
- A Flutter mobile app for device setup, pairing, and WebRTC session management.
- A Node.js signaling server for WebSocket-based peer signaling (Docker-ready for VPS).
- A lightweight web client UI (browser) to connect and manage signaling rooms.
- Supporting deployment and database artifacts.

## Features / Purpose

- Device registration and pairing flow
- WebRTC offer/answer and ICE candidate relay
- Health and stats endpoints for signaling infrastructure
- Docker-based local deployment for the signaling service
- Supabase-compatible backend integration points

## Installation

### Prerequisites

- Flutter SDK 3.0+
- Node.js 18+
- npm
- Docker (optional)

### Clone and bootstrap

```bash
git clone <your-fork-or-repo-url>
cd cooperating-screen
```

## Usage

### Run the Flutter app

```bash
cd cosc
flutter pub get
flutter run
```

### Run the signaling server

```bash
cd signaling_server
npm install
npm run dev
```

The default server endpoint is `ws://localhost:3000`.

## Development Setup

1. Copy environment templates:
   - Root: `.env.example`
   - Signaling server: `signaling_server/.env.example`
2. Create a local runtime config:
   ```bash
   cp signaling_server/.env.example signaling_server/.env
   ```
3. Update Supabase and runtime values for your environment.

## Configuration

Important signaling server environment variables:

- `PORT` (default: `3000`)
- `NODE_ENV` (`development` or `production`)
- `LOG_LEVEL`
- `SUPABASE_URL`
- `SUPABASE_KEY`

Flutter app configuration placeholders live in `cosc/lib/main.dart` and should be replaced with secure runtime configuration for production.

## Build / Run Instructions

### Docker Compose (Backend + Web UI)

```bash
docker-compose up --build
```

- Signaling backend: `ws://localhost:3000`
- Web UI client: `http://localhost:8080`

### Production signaling server

```bash
cd signaling_server
npm install
npm start
```

### Flutter release builds

```bash
cd cosc
flutter build apk
# or
flutter build ios
```

## Troubleshooting

### WebSocket connection issues

- Ensure port `3000` is available.
- Verify the app points to the correct signaling URL.
- Check local firewall/proxy rules.

### Flutter dependency issues

- Run `flutter clean` then `flutter pub get`.
- Confirm Flutter and Dart versions match project constraints.

### Server startup failures

- Validate `.env` values.
- Reinstall dependencies with `npm install`.
- Review logs from `npm run dev`.

## Repository Hygiene

This repository intentionally excludes generated artifacts, local caches, and dependency directories from version control. Regenerate locally using the commands above.

## Additional Documentation

- [Flutter app README](cosc/README.md)
- [Signaling server README](signaling_server/README.md)
- [Contributing guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

Licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
