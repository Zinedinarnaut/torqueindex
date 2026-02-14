# TorqueIndex Full-Stack Project

This repository contains three cleanly separated components:

- `rust-service/`: Internal Shopify aggregation microservice (Axum + Tokio + Reqwest)
- `phoenix-api/`: Public API gateway (Phoenix 1.7 + ETS cache + Rust client)

## Architecture

1. Rust service fetches and normalizes products from predefined Shopify stores.
2. Phoenix API calls Rust internal endpoints and caches query results in ETS.
3. SwiftUI client calls Phoenix API for stores/mod feed/detail.

Backend scraping now paginates each Shopify store endpoint through all pages (bounded by config safety limits).
Scraped results are persisted in PostgreSQL and served from DB-backed query endpoints.

## Quick start

### Run everything with Docker Compose

```bash
cd /Users/zinedinarnaut/Documents/Projects/TorqueIndex
docker compose up --build
```

This starts:
- Rust service on `http://localhost:3001`
- Phoenix API on `http://localhost:4000`

### 1) Run Rust internal service

```bash
cd rust-service
cp .env.example .env
cargo run
```

Service URL: `http://localhost:3001`

### 2) Run Phoenix public API

```bash
cd phoenix-api
mix setup
mix phx.server
```

API URL: `http://localhost:4000`

### 3) Run SwiftUI app

Open `/Users/zinedinarnaut/Documents/Projects/TorqueIndex/swiftui-client/TorqueIndexClient.xcodeproj` in Xcode.
Set `TORQUE_API_BASE_URL=http://localhost:4000/api` in the scheme if needed.

### Access from physical iPhone on the same Wi-Fi

1. Start backend services (`docker compose up` or `mix phx.server` + `cargo run`).
2. Find your Mac LAN IP:
```bash
ipconfig getifaddr en0
```
3. In Xcode scheme for `TorqueIndexClient`, set:
```bash
TORQUE_API_BASE_URL=http://<YOUR_MAC_LAN_IP>:4000/api
```
4. Run on your iPhone (same Wi-Fi as Mac).

Notes:
- Phoenix dev now binds `0.0.0.0:4000`, so LAN devices can reach it.
- Rust binds `0.0.0.0:3001` and is only used internally by Phoenix.
- If connection still fails, allow incoming connections for Docker/Xcode/Phoenix in macOS Firewall.

## API surfaces

### Rust internal endpoints

- `GET /internal/health`
- `GET /internal/stores`
- `GET /internal/mods?make=BMW&model=F20&engine=N20`
- `GET /internal/mods/{id}`

### Phoenix public endpoints

- `GET /api/stores`
- `GET /api/mods?make=&model=&engine=`
- `GET /api/mods/:id`

### Optional WebSocket

- Socket path: `/socket`
- Channel topic scaffold: `mods:lobby`

## Store providers included

- `https://21overlays.com.au`
- `https://dubhaus.com.au`
- `https://modeautoconcepts.com`
- `https://xforce.com.au`
- `https://justjap.com`
- `https://www.modsdirect.com.au`
- `https://www.prospeedracing.com.au`
- `https://shiftymods.com.au`
- `https://hi-torqueperformance.myshopify.com`
- `https://performancewarehouse.com.au`
- `https://streetelement.com.au`
- `https://allautomotiveparts.com.au`
- `https://eziautoparts.com.au`
- `https://autocave.com.au`
- `https://jtmauto.com.au`
- `https://tjautoparts.com.au`
- `https://www.nationwideautoparts.com.au`
- `https://www.chicaneaustralia.com.au`

## Environment knobs

### Rust service

- `RUST_BIND_ADDR` (default: `0.0.0.0:3001`)
- `DATABASE_URL` (Postgres DSN for normalized product storage)
- `SHOPIFY_PAGE_LIMIT` (default: `250`, max `250`)
- `SHOPIFY_MAX_PAGES` (default: `40`)
- `SCRAPE_PAGE_DELAY_MS` (default: `500`)
- `SCRAPE_STORE_CONCURRENCY` (default: `3`)
- `SCRAPE_MAX_429_RETRIES` (default: `6`)
- `SCRAPE_RETRY_BASE_DELAY_MS` (default: `1000`)
- `SCRAPE_REFRESH_INTERVAL_SECS` (default: `900`)
- `STORES_JSON` (optional JSON array override)

### Phoenix API

- `RUST_SERVICE_URL` (default: `http://localhost:3001`)
- `CACHE_TTL_MS` (default: `60000`)
- `STORE_REGISTRY_JSON` (optional JSON array override)
