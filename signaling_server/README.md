# Cooperating Screen Signaling Server

Node.js WebSocket signaling server used by the Cooperating Screen clients.

## Features

- WebSocket signaling for device registration and pairing
- WebRTC SDP/ICE message relay
- Health and stats endpoints
- Basic in-memory request and message rate limiting

## Setup

```bash
cd signaling_server
npm install
cp .env.example .env
npm run dev
```

## Run

```bash
npm start
```

Default endpoint: `ws://localhost:3000`

## Docker

```bash
docker build -t cooperating-screen-signaling-server .
docker run -p 3000:3000 cooperating-screen-signaling-server
```

Or from repo root (backend + web UI):

```bash
docker-compose up --build
```

## Endpoints

- `GET /health`
- `GET /stats`

## Notes

For broader setup and repository policies, see [../README.md](../README.md).
