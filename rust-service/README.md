# Torque Rust Service

Async internal service that aggregates products from multiple Shopify stores, normalizes product payloads, and exposes internal query endpoints.

Scraped products are persisted in PostgreSQL and served from DB-backed query endpoints.

## Build and run

```bash
cd rust-service
cp .env.example .env
cargo run
```

Server defaults to `0.0.0.0:3001`.

## Endpoints

- `GET /internal/health`
- `GET /internal/stores`
- `GET /internal/mods?make=BMW&model=F20&engine=N20`
- `GET /internal/mods/{id}` where id can be full normalized id (`store:product`) or raw Shopify product id.
- `POST /internal/scrape` to trigger an immediate scrape + DB upsert.

## Notes

- Fetches from `{base_url}/products.json?limit={page_limit}&page={n}` concurrently across stores and paginates through all available pages.
- Handles `429 Too Many Requests` with retry + backoff based on `Retry-After` (or exponential fallback).
- Filters tags with case-insensitive matching on `make`, `model`, and `engine`.
- You can override the store list with `STORES_JSON` (JSON array of store objects).
- `DATABASE_URL` points at the Postgres database used to persist normalized products.
- `SHOPIFY_PAGE_LIMIT` controls per-page Shopify fetch size (`1..250`, default `250`).
- `SHOPIFY_MAX_PAGES` controls pagination safety cap per store (default `40`).
- `SCRAPE_PAGE_DELAY_MS` controls delay between page requests for a store (default `500`).
- `SCRAPE_STORE_CONCURRENCY` controls concurrent store scraping workers (default `3`).
- `SCRAPE_MAX_429_RETRIES` controls max retries on HTTP 429 (default `6`).
- `SCRAPE_RETRY_BASE_DELAY_MS` controls base backoff delay for 429 retries (default `1000`).
- `SCRAPE_REFRESH_INTERVAL_SECS` controls periodic background rescrape interval (default `900`).
