# Torque Phoenix API Gateway

Phoenix 1.7+ API gateway exposing public REST endpoints for clients, backed by the Rust internal service.

## Features

- `GET /api/stores`
- `GET /api/mods?make=&model=&engine=`
- `GET /api/mods/:id`
- Auth + profile:
  - `POST /api/auth/signup`
  - `POST /api/auth/signin`
  - `POST /api/auth/refresh`
  - `DELETE /api/auth/signout` (JWT required)
  - `GET /api/profile/me` (JWT required)
  - `PUT /api/profile/me` (JWT required)
  - `POST /api/auth/reset/request`
  - `POST /api/auth/reset/confirm`
- ETS in-memory caching for list/detail queries
- Rust service integration via `Req`
- Optional WebSocket channel scaffold at `/socket` (`mods:lobby`)
- Store registry filtering via config/env

## Setup

```bash
cd phoenix-api
mix setup
mix ecto.migrate
mix phx.server
```

By default the API runs on `http://localhost:4000`.
In development it binds `0.0.0.0:4000`, so devices on your LAN can reach it via your Mac IP.

## Docker

Build and run from repo root:

```bash
docker compose up --build phoenix-api rust-service
```

Run migrations (release):

```bash
docker compose exec -T phoenix-api bin/torque_gateway eval "TorqueGateway.Release.migrate"
```

## Environment variables

- `RUST_SERVICE_URL` (default: `http://localhost:3001`)
- `CACHE_TTL_MS` (default: `60000`)
- `STORE_REGISTRY_JSON` (optional JSON array override)
- `DATABASE_URL` (required in prod/release)
- `JWT_SECRET` (required in prod/release)
- `ACCESS_TOKEN_TTL_SECS` (default: `3600`)
- `REFRESH_TOKEN_TTL_DAYS` (default: `30`)
- `RESET_TOKEN_TTL_SECS` (default: `3600`)
- `PASSWORD_RESET_URL_BASE` (default: `torqueindex://reset?token=`)

Example `STORE_REGISTRY_JSON` value:

```json
[{"id":"21overlays","name":"21 Overlays","base_url":"https://21overlays.com.au"}]
```

## iPhone/LAN usage

If your SwiftUI app runs on a physical iPhone, point it to your Mac IP:

```bash
ipconfig getifaddr en0
```

Then set app env:

```bash
TORQUE_API_BASE_URL=http://<YOUR_MAC_LAN_IP>:4000/api
```
