# TorqueIndex Master API (Rust + Phoenix)

Single reference for both backend layers:
- **Internal data service**: Rust (`axum`) on port `3001`
- **Public gateway**: Phoenix API on port `4000`

---

## 1) Service topology

```text
SwiftUI iOS App
   -> Phoenix API (public): /api/*
      -> Rust Service (internal): /internal/*
         -> PostgreSQL (normalized_mods)
         -> Shopify products.json endpoints (multi-page scraping)
```

Base URLs (default local):
- Rust internal: `http://localhost:3001`
- Phoenix public: `http://localhost:4000/api`
- WebSocket: `ws://localhost:4000/socket/websocket`

Docker service-to-service:
- Phoenix -> Rust: `http://rust-service:3001`

---

## 2) Shared data contracts

### Store

```json
{
  "id": "modeautoconcepts",
  "name": "Mode Auto Concepts",
  "base_url": "https://modeautoconcepts.com",
  "logo_url": "https://modeautoconcepts.com/cdn/shop/files/mode_website_header.png?v=1726554561&width=130"
}
```

### Normalized Mod

```json
{
  "id": "modeautoconcepts:123456789",
  "store_id": "modeautoconcepts",
  "title": "B58 Intake Kit",
  "images": ["https://.../image.jpg"],
  "price": 699.0,
  "vendor": "Example Vendor",
  "product_type": "Air Intake",
  "tags": ["BMW", "F20", "N20"],
  "product_url": "https://modeautoconcepts.com/products/b58-intake-kit"
}
```

### Standard envelopes

Single item envelope:

```json
{
  "data": { "...": "..." }
}
```

List envelope:

```json
{
  "data": [{ "...": "..." }],
  "meta": { "count": 1 }
}
```

Error envelope:

```json
{
  "error": {
    "code": "BAD_REQUEST",
    "message": "At least one filter is required: make, model, or engine"
  }
}
```

---

## 3) Rust internal API (`/internal/*`)

### GET `/internal/health`
Purpose: liveness check.

Success `200`:

```json
{ "data": "ok" }
```

### GET `/internal/stores`
Purpose: returns configured Shopify stores.

Success `200`:

```json
{
  "data": [
    {
      "id": "21overlays",
      "name": "21 Overlays",
      "base_url": "https://21overlays.com.au",
      "logo_url": null
    }
  ]
}
```

### GET `/internal/mods?make=&model=&engine=`
Purpose: query normalized mods from PostgreSQL using compatibility filtering.

Rules:
- At least one of `make`, `model`, `engine` is required.
- Matching is case-insensitive.
- Uses normalized text matching over title/vendor/product_type/tags.
- If DB is empty, service auto-runs a seed scrape first.

Success `200`:

```json
{
  "data": [
    {
      "id": "modeautoconcepts:123456789",
      "store_id": "modeautoconcepts",
      "title": "B58 Intake Kit",
      "images": ["https://..."],
      "price": 699.0,
      "vendor": "Vendor",
      "product_type": "Air Intake",
      "tags": ["BMW", "F20", "N20"],
      "product_url": "https://..."
    }
  ],
  "meta": { "count": 1 }
}
```

Common errors:
- `400 BAD_REQUEST` if no filter provided
- `502 UPSTREAM_ERROR` if all store fetches fail during scrape/seed
- `500 DATABASE_ERROR` for DB failures

### GET `/internal/mods/:id`
Purpose: fetch a single mod.

Accepted `:id` forms:
- Full normalized id: `store_id:shopify_product_id`
- Raw Shopify product id: `shopify_product_id`

Success `200`:

```json
{ "data": { "id": "modeautoconcepts:123456789", "...": "..." } }
```

Errors:
- `404 NOT_FOUND`
- `500 DATABASE_ERROR`

### POST `/internal/scrape`
Purpose: trigger immediate scrape + upsert for all stores.

Success `200`:

```json
{
  "data": {
    "stores_total": 18,
    "stores_succeeded": 17,
    "stores_failed": 1,
    "mods_upserted": 14325
  }
}
```

Errors:
- `502 UPSTREAM_ERROR` if every store fails
- `500 DATABASE_ERROR`

---

## 4) Phoenix public API (`/api/*`)

Phoenix is the client-facing gateway. It calls Rust, applies store registry filtering, and caches results in ETS.

### GET `/api/stores`
Purpose: list enabled stores for clients.

Success `200`:

```json
{
  "data": [
    {
      "id": "21overlays",
      "name": "21 Overlays",
      "base_url": "https://21overlays.com.au",
      "logo_url": "http://localhost:4000/store_logos/21overlays.png"
    }
  ]
}
```

### GET `/api/mods?make=&model=&engine=`
Purpose: list mods from Rust, filtered to enabled stores, cached by query tuple.

Rules:
- Requires at least one filter (`make`, `model`, `engine`).
- Cache key: `{:mods, make, model, engine}`

Success `200`:

```json
{
  "data": [
    {
      "id": "modeautoconcepts:123456789",
      "store_id": "modeautoconcepts",
      "title": "B58 Intake Kit",
      "images": ["https://..."],
      "price": 699.0,
      "vendor": "Vendor",
      "product_type": "Air Intake",
      "tags": ["BMW", "F20", "N20"],
      "product_url": "https://..."
    }
  ],
  "meta": { "count": 1 }
}
```

Errors:
- `400 BAD_REQUEST` if all filters missing
- `502 UPSTREAM_ERROR` on Rust upstream failure
- `404 NOT_FOUND` if upstream not found
- `500 INTERNAL_ERROR` for unclassified failures

### GET `/api/mods/:id`
Purpose: single mod lookup via Rust + registry enforcement + ETS cache.

Behavior:
- Cache key: `{:mod, id}`
- If Rust returns a mod for a store not enabled in registry, response is `404`.

Success `200`:

```json
{ "data": { "id": "modeautoconcepts:123456789", "...": "..." } }
```

Errors:
- `404 NOT_FOUND`
- `502 UPSTREAM_ERROR`
- `500 INTERNAL_ERROR`

---

## 4.1) Auth + Profile (Phoenix)

Phoenix is authoritative for authentication and user profiles. Rust remains unauthenticated/internal.

JWT usage:
- Send access token as `Authorization: Bearer <JWT>`
- Access token TTL default: `3600s`
- Refresh token TTL default: `30 days` (rotated on every refresh)

### POST `/api/auth/signup`

Request:

```json
{ "email": "zinedin@example.com", "username": "zinedin", "password": "password123" }
```

Response `200`:

```json
{
  "access_token": "JWT_HERE",
  "refresh_token": "REFRESH_TOKEN_HERE",
  "profile": { "id": "...", "email": "...", "username": "...", "verified": false }
}
```

### POST `/api/auth/signin`

Request:

```json
{ "email": "zinedin@example.com", "password": "password123" }
```

Response `200`: same shape as signup.

Errors:
- `401 UNAUTHORIZED` invalid credentials
- `429 RATE_LIMITED` too many attempts

### POST `/api/auth/refresh`

Request:

```json
{ "refresh_token": "REFRESH_TOKEN_HERE" }
```

Response `200`: new `access_token` + rotated `refresh_token` + `profile`.

Errors:
- `401 UNAUTHORIZED` invalid/expired/revoked refresh token

### DELETE `/api/auth/signout` (JWT required)

Optional request body (revoke one refresh token):

```json
{ "refresh_token": "REFRESH_TOKEN_HERE" }
```

If no `refresh_token` is provided, all active sessions for the current user are revoked.

Response `200`:

```json
{ "data": "ok" }
```

### GET `/api/profile/me` (JWT required)

Response `200`:

```json
{ "data": { "id": "...", "email": "...", "username": "...", "verified": false } }
```

### PUT `/api/profile/me` (JWT required)

Request:

```json
{ "email": "zinedin@example.com", "username": "zinedin" }
```

Response `200`:

```json
{ "data": { "id": "...", "email": "...", "username": "..." } }
```

### POST `/api/auth/reset/request`

Request:

```json
{ "email": "zinedin@example.com" }
```

Response `200`:

```json
{ "data": "ok" }
```

Note: always returns `ok` (prevents email enumeration).

### POST `/api/auth/reset/confirm`

Request:

```json
{ "token": "RESET_TOKEN_HERE", "password": "new_password_123" }
```

Response `200`:

```json
{ "data": "ok" }
```

---

## 5) Optional WebSocket (Phoenix Channels)

Socket endpoint:
- `/socket` (websocket enabled)

Topic support:
- `mods:lobby` join allowed
- `mods:*` (other topics) rejected as unauthorized

### Join `mods:lobby`
Server reply:

```json
{ "message": "connected" }
```

### `ping` event
Client sends:

```json
{"event":"ping","payload":{"hello":"world"}}
```

Server replies with same payload.

---

## 6) Config reference

### Rust service env

- `RUST_BIND_ADDR` default `0.0.0.0:3001`
- `DATABASE_URL` Postgres connection string
- `STORES_JSON` optional JSON override for store list
- `SHOPIFY_PAGE_LIMIT` default `250` (range `1..250`)
- `SHOPIFY_MAX_PAGES` default `40`
- `SCRAPE_PAGE_DELAY_MS` default `500`
- `SCRAPE_STORE_CONCURRENCY` default `3`
- `SCRAPE_MAX_429_RETRIES` default `6`
- `SCRAPE_RETRY_BASE_DELAY_MS` default `1000`
- `SCRAPE_REFRESH_INTERVAL_SECS` default `900`

### Phoenix env

- `RUST_SERVICE_URL` default `http://localhost:3001`
- `CACHE_TTL_MS` default `60000`
- `STORE_REGISTRY_JSON` optional JSON array override
- `PORT` default `4000`
- `PHX_HOST` default `localhost`
- `SECRET_KEY_BASE` required in prod

---

## 7) Operational behavior notes

- Rust periodically scrapes all configured stores in background.
- Rust scraper is lock-protected to avoid concurrent overlapping scrape jobs.
- Rust handles Shopify `429` with `Retry-After` support and exponential backoff fallback.
- Rust upserts store data and prunes stale products per store.
- Phoenix cache is ETS-based with TTL expiration and periodic cleanup.
- Phoenix can hide stores/mods via `store_registry` configuration without changing Rust.

---

## 8) Quick smoke test commands

```bash
# Rust
curl http://localhost:3001/internal/health
curl http://localhost:3001/internal/stores
curl "http://localhost:3001/internal/mods?make=BMW&model=F20&engine=N20"
curl -X POST http://localhost:3001/internal/scrape

# Phoenix
curl http://localhost:4000/api/stores
curl "http://localhost:4000/api/mods?make=BMW&model=F20&engine=N20"
curl http://localhost:4000/api/mods/modeautoconcepts:123456789
```
