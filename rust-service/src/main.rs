use std::{collections::HashSet, env, net::SocketAddr, sync::Arc, time::Duration};

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use dotenvy::dotenv;
use futures::{stream, StreamExt};
use reqwest::{header, Client};
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, types::Json as SqlJson, PgPool, Postgres, QueryBuilder, Row};
use thiserror::Error;
use tokio::sync::Mutex;
use tokio::time::sleep;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Store {
    id: String,
    name: String,
    base_url: String,
    #[serde(default)]
    logo_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct NormalizedMod {
    id: String,
    store_id: String,
    title: String,
    images: Vec<String>,
    price: f64,
    vendor: String,
    product_type: String,
    tags: Vec<String>,
    product_url: String,
}

#[derive(Debug, Clone, Serialize)]
struct ScrapeStats {
    stores_total: usize,
    stores_succeeded: usize,
    stores_failed: usize,
    mods_upserted: usize,
}

#[derive(Debug, Deserialize)]
struct ShopifyProductsResponse {
    products: Vec<ShopifyProduct>,
}

#[derive(Debug, Deserialize)]
struct ShopifyProduct {
    id: i64,
    title: String,
    handle: String,
    vendor: Option<String>,
    #[serde(default)]
    product_type: String,
    #[serde(default)]
    tags: ShopifyTags,
    #[serde(default)]
    images: Vec<ShopifyImage>,
    #[serde(default)]
    variants: Vec<ShopifyVariant>,
}

#[derive(Debug, Deserialize)]
struct ShopifyImage {
    src: String,
}

#[derive(Debug, Deserialize)]
struct ShopifyVariant {
    price: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum ShopifyTags {
    String(String),
    Array(Vec<String>),
}

impl Default for ShopifyTags {
    fn default() -> Self {
        Self::Array(Vec::new())
    }
}

#[derive(Debug, Deserialize)]
struct ModsQuery {
    make: Option<String>,
    model: Option<String>,
    engine: Option<String>,
}

#[derive(Debug, Serialize)]
struct ApiResponse<T> {
    data: T,
}

#[derive(Debug, Serialize)]
struct ListResponse<T> {
    data: Vec<T>,
    meta: ListMeta,
}

#[derive(Debug, Serialize)]
struct ListMeta {
    count: usize,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: ErrorBody,
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    code: &'static str,
    message: String,
}

#[derive(Debug, Clone)]
struct ScrapeConfig {
    page_limit: usize,
    max_pages: usize,
    page_delay: Duration,
    store_concurrency: usize,
    max_429_retries: usize,
    retry_base_delay: Duration,
    refresh_interval: Duration,
}

#[derive(Debug, Clone)]
struct AppState {
    stores: Vec<Store>,
    http_client: Client,
    db_pool: PgPool,
    scrape_config: ScrapeConfig,
    scrape_lock: Arc<Mutex<()>>,
}

#[derive(Debug, Error)]
enum AppError {
    #[error("Product not found")]
    NotFound,
    #[error("Upstream request failed: {0}")]
    Upstream(String),
    #[error("Invalid request: {0}")]
    BadRequest(String),
    #[error("Database error: {0}")]
    Database(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            AppError::NotFound => (
                StatusCode::NOT_FOUND,
                "NOT_FOUND",
                "Requested resource was not found".to_string(),
            ),
            AppError::Upstream(message) => (StatusCode::BAD_GATEWAY, "UPSTREAM_ERROR", message),
            AppError::BadRequest(message) => (StatusCode::BAD_REQUEST, "BAD_REQUEST", message),
            AppError::Database(_message) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "DATABASE_ERROR",
                "Database operation failed".to_string(),
            ),
        };

        (
            status,
            Json(ErrorResponse {
                error: ErrorBody { code, message },
            }),
        )
            .into_response()
    }
}

#[tokio::main]
async fn main() {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "torque_rust_service=info,axum=info,sqlx=warn".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let bind_addr = env::var("RUST_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:3001".to_string());
    let stores = load_stores().expect("failed to load store registry");

    let database_url = env::var("DATABASE_URL").expect(
        "DATABASE_URL is missing. Example: postgres://USER:PASS@HOST:5432/DBNAME?sslmode=disable",
    );

    let db_pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&database_url)
        .await
        .expect("failed to connect to postgres");

    init_db(&db_pool).await.expect("failed to initialize database");

    let http_client = Client::builder()
        .user_agent("torque-rust-service/0.2")
        .timeout(Duration::from_secs(20))
        .build()
        .expect("failed to build reqwest client");

    let scrape_config = load_scrape_config();

    let app_state = AppState {
        stores,
        http_client,
        db_pool,
        scrape_config,
        scrape_lock: Arc::new(Mutex::new(())),
    };

    spawn_periodic_scraper(app_state.clone());

    let app = Router::new()
        .route("/internal/health", get(health))
        .route("/internal/stores", get(get_stores))
        .route("/internal/mods", get(get_mods))
        .route("/internal/mods/:id", get(get_mod_by_id))
        .route("/internal/scrape", post(trigger_scrape))
        .with_state(app_state);

    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .expect("failed to bind address");

    let local_addr: SocketAddr = listener
        .local_addr()
        .expect("failed to read listening socket address");
    tracing::info!("Rust service listening on {}", local_addr);

    if let Err(error) = axum::serve(listener, app).await {
        error!("server failed: {error}");
    }
}

fn spawn_periodic_scraper(state: AppState) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(state.scrape_config.refresh_interval);

        loop {
            ticker.tick().await;

            match run_scrape_job(&state).await {
                Ok(stats) => info!(
                    "scheduled scrape completed: stores_succeeded={} stores_failed={} mods_upserted={}",
                    stats.stores_succeeded, stats.stores_failed, stats.mods_upserted
                ),
                Err(error) => warn!("scheduled scrape failed: {error}"),
            }
        }
    });
}

async fn health() -> Json<ApiResponse<&'static str>> {
    Json(ApiResponse { data: "ok" })
}

async fn get_stores(State(state): State<AppState>) -> Json<ApiResponse<Vec<Store>>> {
    Json(ApiResponse {
        data: state.stores.clone(),
    })
}

async fn trigger_scrape(State(state): State<AppState>) -> Result<Json<ApiResponse<ScrapeStats>>, AppError> {
    let stats = run_scrape_job(&state).await?;
    Ok(Json(ApiResponse { data: stats }))
}

async fn get_mods(
    State(state): State<AppState>,
    Query(query): Query<ModsQuery>,
) -> Result<Json<ListResponse<NormalizedMod>>, AppError> {
    if query.make.is_none() && query.model.is_none() && query.engine.is_none() {
        return Err(AppError::BadRequest(
            "At least one filter must be provided: make, model, or engine".to_string(),
        ));
    }

    ensure_seed_data(&state).await?;

    let filtered = query_mods_from_db(&state.db_pool, &query).await?;

    Ok(Json(ListResponse {
        meta: ListMeta {
            count: filtered.len(),
        },
        data: filtered,
    }))
}

async fn get_mod_by_id(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<ApiResponse<NormalizedMod>>, AppError> {
    ensure_seed_data(&state).await?;

    let matched = find_mod_by_id(&state.db_pool, &id).await?;

    match matched {
        Some(item) => Ok(Json(ApiResponse { data: item })),
        None => Err(AppError::NotFound),
    }
}

async fn ensure_seed_data(state: &AppState) -> Result<(), AppError> {
    let count = count_mods(&state.db_pool).await?;

    if count == 0 {
        let stats = run_scrape_job(state).await?;
        info!(
            "seed scrape completed: stores_succeeded={} stores_failed={} mods_upserted={}",
            stats.stores_succeeded, stats.stores_failed, stats.mods_upserted
        );
    }

    Ok(())
}

async fn run_scrape_job(state: &AppState) -> Result<ScrapeStats, AppError> {
    let _guard = state.scrape_lock.lock().await;
    scrape_and_persist_all_stores(state).await
}

async fn scrape_and_persist_all_stores(state: &AppState) -> Result<ScrapeStats, AppError> {
    let stores_total = state.stores.len();
    let mut stores_succeeded = 0_usize;
    let mut stores_failed = 0_usize;
    let mut mods_upserted = 0_usize;

    let jobs = stream::iter(state.stores.iter().cloned().map(|store| {
        let client = state.http_client.clone();
        let scrape_cfg = state.scrape_config.clone();
        async move {
            let result = fetch_store_mods(client, scrape_cfg, store.clone()).await;
            (store, result)
        }
    }))
    .buffer_unordered(state.scrape_config.store_concurrency.max(1));

    tokio::pin!(jobs);

    while let Some((store, result)) = jobs.next().await {
        match result {
            Ok(mods) => {
                let upserted = mods.len();
                upsert_store_mods(&state.db_pool, &store.id, &mods).await?;
                stores_succeeded += 1;
                mods_upserted += upserted;
            }
            Err(error) => {
                stores_failed += 1;
                warn!("failed to fetch store products: {error}");
            }
        }
    }

    if stores_succeeded == 0 && stores_failed > 0 {
        return Err(AppError::Upstream(
            "Failed to fetch products from all configured stores".to_string(),
        ));
    }

    Ok(ScrapeStats {
        stores_total,
        stores_succeeded,
        stores_failed,
        mods_upserted,
    })
}

async fn fetch_store_mods(
    client: Client,
    scrape_cfg: ScrapeConfig,
    store: Store,
) -> Result<Vec<NormalizedMod>, AppError> {
    let mut page = 1_usize;
    let mut collected = Vec::new();
    let mut seen_product_ids = HashSet::new();

    loop {
        let payload = match fetch_page_payload(&client, &scrape_cfg, &store, page).await {
            Ok(payload) => payload,
            Err(error) => {
                if page == 1 {
                    return Err(error);
                }

                warn!(
                    "stopping pagination for store '{}' at page {} due to error: {}",
                    store.id, page, error
                );
                break;
            }
        };

        let fetched_count = payload.products.len();
        if fetched_count == 0 {
            break;
        }

        let mut new_products = 0_usize;
        for product in payload.products {
            if seen_product_ids.insert(product.id) {
                collected.push(normalize_product(product, &store));
                new_products += 1;
            }
        }

        if new_products == 0 {
            warn!(
                "stopping pagination for store '{}' at page {} because no new products were discovered",
                store.id, page
            );
            break;
        }

        if fetched_count < scrape_cfg.page_limit {
            break;
        }

        page += 1;
        if page > scrape_cfg.max_pages {
            warn!(
                "stopping pagination for store '{}' after reaching SHOPIFY_MAX_PAGES={}",
                store.id, scrape_cfg.max_pages
            );
            break;
        }

        if !scrape_cfg.page_delay.is_zero() {
            sleep(scrape_cfg.page_delay).await;
        }
    }

    Ok(collected)
}

async fn fetch_page_payload(
    client: &Client,
    scrape_cfg: &ScrapeConfig,
    store: &Store,
    page: usize,
) -> Result<ShopifyProductsResponse, AppError> {
    let url = format!(
        "{}/products.json?limit={}&page={}",
        store.base_url.trim_end_matches('/'),
        scrape_cfg.page_limit,
        page
    );

    let mut attempt = 0_usize;

    loop {
        let response = client
            .get(&url)
            .send()
            .await
            .map_err(|error| AppError::Upstream(format!("{} ({})", store.id, error)))?;

        if response.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
            if attempt >= scrape_cfg.max_429_retries {
                return Err(AppError::Upstream(format!(
                    "{} (HTTP 429 Too Many Requests for url ({}))",
                    store.id, url
                )));
            }

            let delay = retry_delay_for_429(&response, scrape_cfg, attempt);
            warn!(
                "rate limited by store '{}' on page {} (attempt {}), backing off for {:?}",
                store.id,
                page,
                attempt + 1,
                delay
            );
            sleep(delay).await;
            attempt += 1;
            continue;
        }

        let response = response.error_for_status().map_err(|error| {
            AppError::Upstream(format!(
                "{} (HTTP status client/server error ({}) for url ({}))",
                store.id, error, url
            ))
        })?;

        let payload = response
            .json::<ShopifyProductsResponse>()
            .await
            .map_err(|error| AppError::Upstream(format!("{} ({})", store.id, error)))?;

        return Ok(payload);
    }
}

fn retry_delay_for_429(response: &reqwest::Response, scrape_cfg: &ScrapeConfig, attempt: usize) -> Duration {
    if let Some(seconds) = response
        .headers()
        .get(header::RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .and_then(|raw| raw.parse::<u64>().ok())
    {
        return Duration::from_secs(seconds.clamp(1, 120));
    }

    let exp = 2_u64.saturating_pow(attempt as u32);
    let millis = (scrape_cfg.retry_base_delay.as_millis() as u64)
        .saturating_mul(exp)
        .clamp(250, 30_000);

    Duration::from_millis(millis)
}

fn normalize_product(product: ShopifyProduct, store: &Store) -> NormalizedMod {
    let tags = normalize_tags(product.tags);
    let images = product.images.into_iter().map(|image| image.src).collect();
    let price = extract_price(&product.variants);

    NormalizedMod {
        id: format!("{}:{}", store.id, product.id),
        store_id: store.id.clone(),
        title: product.title,
        images,
        price,
        vendor: product.vendor.unwrap_or_else(|| "Unknown".to_string()),
        product_type: product.product_type,
        tags,
        product_url: format!(
            "{}/products/{}",
            store.base_url.trim_end_matches('/'),
            product.handle
        ),
    }
}

fn normalize_tags(raw_tags: ShopifyTags) -> Vec<String> {
    match raw_tags {
        ShopifyTags::String(raw) => raw
            .split(',')
            .map(str::trim)
            .filter(|tag| !tag.is_empty())
            .map(ToString::to_string)
            .collect(),
        ShopifyTags::Array(values) => values
            .into_iter()
            .map(|tag| tag.trim().to_string())
            .filter(|tag| !tag.is_empty())
            .collect(),
    }
}

fn extract_price(variants: &[ShopifyVariant]) -> f64 {
    variants
        .iter()
        .find_map(|variant| variant.price.as_ref())
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(0.0)
}

fn matches_filters(item: &NormalizedMod, query: &ModsQuery) -> bool {
    let haystacks = build_search_haystacks(item);

    if let Some(make_filter) = query
        .make
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        if !matches_simple_value(&haystacks, &make_filter) {
            return false;
        }
    }

    if let Some(model_filter) = query
        .model
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        if !matches_model_filter(&haystacks, &model_filter) {
            return false;
        }
    }

    if let Some(engine_filter) = query
        .engine
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        if !matches_engine_filter(&haystacks, &engine_filter) {
            return false;
        }
    }

    true
}

fn build_search_haystacks(item: &NormalizedMod) -> Vec<String> {
    let mut haystacks = Vec::with_capacity(item.tags.len() + 3);

    for source in [
        item.title.as_str(),
        item.vendor.as_str(),
        item.product_type.as_str(),
    ] {
        let normalized = normalize_match_text(source);
        if !normalized.is_empty() {
            haystacks.push(normalized);
        }
    }

    haystacks.extend(
        item.tags
            .iter()
            .map(|tag| normalize_match_text(tag))
            .filter(|tag| !tag.is_empty()),
    );

    haystacks
}

fn matches_simple_value(haystacks: &[String], filter_value: &str) -> bool {
    haystacks.iter().any(|haystack| {
        haystack.contains(filter_value)
            || haystack
                .split_whitespace()
                .any(|token| token.eq_ignore_ascii_case(filter_value))
    })
}

fn matches_model_filter(haystacks: &[String], model_filter: &str) -> bool {
    if matches_simple_value(haystacks, model_filter) {
        return true;
    }

    let model_tokens: Vec<&str> = model_filter.split_whitespace().collect();
    if model_tokens.is_empty() {
        return false;
    }

    let chassis_tokens: Vec<&str> = model_tokens
        .iter()
        .copied()
        .filter(|token| token_has_letters_and_digits(token))
        .collect();

    if !chassis_tokens.is_empty() {
        return chassis_tokens
            .iter()
            .any(|token| matches_simple_value(haystacks, token));
    }

    let meaningful_tokens: Vec<&str> = model_tokens
        .iter()
        .copied()
        .filter(|token| token.len() >= 3 && *token != "series")
        .collect();

    if meaningful_tokens.is_empty() {
        return false;
    }

    let matches = meaningful_tokens
        .iter()
        .filter(|token| matches_simple_value(haystacks, token))
        .count();

    matches * 2 >= meaningful_tokens.len()
}

fn matches_engine_filter(haystacks: &[String], engine_filter: &str) -> bool {
    if matches_simple_value(haystacks, engine_filter) {
        return true;
    }

    let compact_filter = engine_filter.replace(' ', "");
    if compact_filter.is_empty() {
        return false;
    }

    haystacks.iter().any(|haystack| {
        let compact_haystack = haystack.replace(' ', "");
        compact_haystack.contains(&compact_filter)
    })
}

fn token_has_letters_and_digits(token: &str) -> bool {
    let has_alpha = token.chars().any(|ch| ch.is_ascii_alphabetic());
    let has_digit = token.chars().any(|ch| ch.is_ascii_digit());
    has_alpha && has_digit
}

fn normalize_match_text(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_lowercase()
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
}

fn load_stores() -> Result<Vec<Store>, AppError> {
    if let Ok(raw_json) = env::var("STORES_JSON") {
        let stores = serde_json::from_str::<Vec<Store>>(&raw_json)
            .map_err(|error| AppError::BadRequest(format!("Invalid STORES_JSON: {error}")))?;
        if stores.is_empty() {
            return Err(AppError::BadRequest(
                "STORES_JSON cannot be an empty list".to_string(),
            ));
        }

        return Ok(stores);
    }

    Ok(default_stores())
}

fn load_scrape_config() -> ScrapeConfig {
    ScrapeConfig {
        page_limit: parse_env_usize("SHOPIFY_PAGE_LIMIT", 250, 1, 250),
        max_pages: parse_env_usize("SHOPIFY_MAX_PAGES", 40, 1, 250),
        page_delay: Duration::from_millis(parse_env_u64("SCRAPE_PAGE_DELAY_MS", 500, 0, 30_000)),
        store_concurrency: parse_env_usize("SCRAPE_STORE_CONCURRENCY", 3, 1, 32),
        max_429_retries: parse_env_usize("SCRAPE_MAX_429_RETRIES", 6, 0, 20),
        retry_base_delay: Duration::from_millis(parse_env_u64(
            "SCRAPE_RETRY_BASE_DELAY_MS",
            1_000,
            100,
            60_000,
        )),
        refresh_interval: Duration::from_secs(parse_env_u64(
            "SCRAPE_REFRESH_INTERVAL_SECS",
            900,
            30,
            86_400,
        )),
    }
}

fn parse_env_usize(key: &str, default: usize, min: usize, max: usize) -> usize {
    match env::var(key) {
        Ok(raw) => match raw.parse::<usize>() {
            Ok(value) if value >= min && value <= max => value,
            _ => {
                warn!(
                    "invalid value for {}='{}', using default {}",
                    key, raw, default
                );
                default
            }
        },
        Err(_) => default,
    }
}

fn parse_env_u64(key: &str, default: u64, min: u64, max: u64) -> u64 {
    match env::var(key) {
        Ok(raw) => match raw.parse::<u64>() {
            Ok(value) if value >= min && value <= max => value,
            _ => {
                warn!(
                    "invalid value for {}='{}', using default {}",
                    key, raw, default
                );
                default
            }
        },
        Err(_) => default,
    }
}

async fn init_db(pool: &PgPool) -> Result<(), AppError> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS normalized_mods (
            id TEXT PRIMARY KEY,
            store_id TEXT NOT NULL,
            title TEXT NOT NULL,
            images JSONB NOT NULL DEFAULT '[]'::jsonb,
            price DOUBLE PRECISION NOT NULL DEFAULT 0,
            vendor TEXT NOT NULL,
            product_type TEXT NOT NULL,
            tags JSONB NOT NULL DEFAULT '[]'::jsonb,
            product_url TEXT NOT NULL,
            search_text TEXT NOT NULL DEFAULT '',
            search_compact TEXT NOT NULL DEFAULT '',
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        "#,
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database init failed: {error}");
        AppError::Database("failed to initialize schema".to_string())
    })?;

    sqlx::query("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        .execute(pool)
        .await
        .map_err(|error| {
            error!("database extension init failed: {error}");
            AppError::Database("failed to initialize database extensions".to_string())
        })?;

    sqlx::query("ALTER TABLE normalized_mods ADD COLUMN IF NOT EXISTS search_text TEXT NOT NULL DEFAULT ''")
        .execute(pool)
        .await
        .map_err(|error| {
            error!("database schema update failed: {error}");
            AppError::Database("failed to migrate schema".to_string())
        })?;

    sqlx::query(
        "ALTER TABLE normalized_mods ADD COLUMN IF NOT EXISTS search_compact TEXT NOT NULL DEFAULT ''",
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database schema update failed: {error}");
        AppError::Database("failed to migrate schema".to_string())
    })?;

    sqlx::query(
        r#"
        WITH computed AS (
            SELECT
                id,
                trim(
                    regexp_replace(
                        regexp_replace(
                            lower(
                                coalesce(title, '') || ' ' ||
                                coalesce(vendor, '') || ' ' ||
                                coalesce(product_type, '') || ' ' ||
                                coalesce(tags::text, '')
                            ),
                            '[^a-z0-9]+',
                            ' ',
                            'g'
                        ),
                        '\s+',
                        ' ',
                        'g'
                    )
                ) AS st
            FROM normalized_mods
            WHERE search_text = '' OR search_text IS NULL
        )
        UPDATE normalized_mods m
        SET
            search_text = c.st,
            search_compact = replace(c.st, ' ', '')
        FROM computed c
        WHERE m.id = c.id
        "#,
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database backfill failed: {error}");
        AppError::Database("failed to backfill search index".to_string())
    })?;

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_normalized_mods_store_id ON normalized_mods(store_id)")
        .execute(pool)
        .await
        .map_err(|error| {
            error!("database index init failed: {error}");
            AppError::Database("failed to initialize indices".to_string())
        })?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_normalized_mods_store_updated_at ON normalized_mods(store_id, updated_at DESC)",
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database index init failed: {error}");
        AppError::Database("failed to initialize indices".to_string())
    })?;

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_normalized_mods_updated_at ON normalized_mods(updated_at)")
        .execute(pool)
        .await
        .map_err(|error| {
            error!("database index init failed: {error}");
            AppError::Database("failed to initialize indices".to_string())
        })?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_normalized_mods_shopify_id ON normalized_mods ((split_part(id, ':', 2)))",
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database index init failed: {error}");
        AppError::Database("failed to initialize indices".to_string())
    })?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_normalized_mods_search_text_trgm ON normalized_mods USING GIN (search_text gin_trgm_ops)",
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database index init failed: {error}");
        AppError::Database("failed to initialize indices".to_string())
    })?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_normalized_mods_search_compact_trgm ON normalized_mods USING GIN (search_compact gin_trgm_ops)",
    )
    .execute(pool)
    .await
    .map_err(|error| {
        error!("database index init failed: {error}");
        AppError::Database("failed to initialize indices".to_string())
    })?;

    Ok(())
}

async fn count_mods(pool: &PgPool) -> Result<i64, AppError> {
    let row = sqlx::query("SELECT COUNT(*) AS count FROM normalized_mods")
        .fetch_one(pool)
        .await
        .map_err(|error| {
            error!("database count query failed: {error}");
            AppError::Database("failed to count products".to_string())
        })?;

    row.try_get::<i64, _>("count").map_err(|error| {
        error!("database count decode failed: {error}");
        AppError::Database("failed to decode count".to_string())
    })
}

async fn load_all_mods_from_db(pool: &PgPool) -> Result<Vec<NormalizedMod>, AppError> {
    let rows = sqlx::query(
        r#"
        SELECT id, store_id, title, images, price, vendor, product_type, tags, product_url
        FROM normalized_mods
        "#,
    )
    .fetch_all(pool)
    .await
    .map_err(|error| {
        error!("database read query failed: {error}");
        AppError::Database("failed to load products".to_string())
    })?;

    rows.into_iter()
        .map(row_to_mod)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| {
            error!("database row decode failed: {error}");
            AppError::Database("failed to decode products".to_string())
        })
}

async fn query_mods_from_db(pool: &PgPool, query: &ModsQuery) -> Result<Vec<NormalizedMod>, AppError> {
    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new(
        r#"
        SELECT id, store_id, title, images, price, vendor, product_type, tags, product_url
        FROM normalized_mods
        WHERE 1=1
        "#,
    );

    if let Some(make_filter) = query
        .make
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        qb.push(" AND search_text LIKE ");
        qb.push_bind(format!("%{}%", make_filter));
    }

    if let Some(model_filter) = query
        .model
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        let model_tokens: Vec<&str> = model_filter.split_whitespace().collect();

        if model_tokens.is_empty() {
            qb.push(" AND FALSE");
        } else {
            let chassis_tokens: Vec<&str> = model_tokens
                .iter()
                .copied()
                .filter(|token| token_has_letters_and_digits(token))
                .collect();

            if !chassis_tokens.is_empty() {
                qb.push(" AND (search_text LIKE ");
                qb.push_bind(format!("%{}%", model_filter));

                for token in chassis_tokens {
                    qb.push(" OR search_text LIKE ");
                    qb.push_bind(format!("%{}%", token));
                }

                qb.push(")");
            } else {
                let meaningful_tokens: Vec<&str> = model_tokens
                    .iter()
                    .copied()
                    .filter(|token| token.len() >= 3 && *token != "series")
                    .collect();

                if meaningful_tokens.is_empty() {
                    qb.push(" AND FALSE");
                } else {
                    let threshold = ((meaningful_tokens.len() + 1) / 2) as i64;

                    qb.push(" AND (search_text LIKE ");
                    qb.push_bind(format!("%{}%", model_filter));
                    qb.push(" OR (");

                    for (idx, token) in meaningful_tokens.iter().enumerate() {
                        if idx > 0 {
                            qb.push(" + ");
                        }
                        qb.push("CASE WHEN search_text LIKE ");
                        qb.push_bind(format!("%{}%", token));
                        qb.push(" THEN 1 ELSE 0 END");
                    }

                    qb.push(") >= ");
                    qb.push_bind(threshold);
                    qb.push(")");
                }
            }
        }
    }

    if let Some(engine_filter) = query
        .engine
        .as_ref()
        .map(|value| normalize_match_text(value))
        .filter(|value| !value.is_empty())
    {
        let compact_filter = engine_filter.replace(' ', "");
        qb.push(" AND (search_text LIKE ");
        qb.push_bind(format!("%{}%", engine_filter));

        if !compact_filter.is_empty() {
            qb.push(" OR search_compact LIKE ");
            qb.push_bind(format!("%{}%", compact_filter));
        }

        qb.push(")");
    }

    qb.push(" ORDER BY updated_at DESC");

    let rows = qb.build().fetch_all(pool).await.map_err(|error| {
        error!("database read query failed: {error}");
        AppError::Database("failed to load products".to_string())
    })?;

    rows.into_iter()
        .map(row_to_mod)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| {
            error!("database row decode failed: {error}");
            AppError::Database("failed to decode products".to_string())
        })
}

async fn find_mod_by_id(pool: &PgPool, id: &str) -> Result<Option<NormalizedMod>, AppError> {
    let row = sqlx::query(
        r#"
        SELECT id, store_id, title, images, price, vendor, product_type, tags, product_url
        FROM normalized_mods
        WHERE id = $1
           OR split_part(id, ':', 2) = $1
        LIMIT 1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(|error| {
        error!("database find query failed: {error}");
        AppError::Database("failed to load product".to_string())
    })?;

    match row {
        Some(row) => row_to_mod(row).map(Some).map_err(|error| {
            error!("database row decode failed: {error}");
            AppError::Database("failed to decode product".to_string())
        }),
        None => Ok(None),
    }
}

fn row_to_mod(row: sqlx::postgres::PgRow) -> Result<NormalizedMod, sqlx::Error> {
    let images: SqlJson<Vec<String>> = row.try_get("images")?;
    let tags: SqlJson<Vec<String>> = row.try_get("tags")?;

    Ok(NormalizedMod {
        id: row.try_get("id")?,
        store_id: row.try_get("store_id")?,
        title: row.try_get("title")?,
        images: images.0,
        price: row.try_get("price")?,
        vendor: row.try_get("vendor")?,
        product_type: row.try_get("product_type")?,
        tags: tags.0,
        product_url: row.try_get("product_url")?,
    })
}

async fn upsert_store_mods(pool: &PgPool, store_id: &str, mods: &[NormalizedMod]) -> Result<(), AppError> {
    let mut tx = pool.begin().await.map_err(|error| {
        error!("database transaction start failed: {error}");
        AppError::Database("failed to start transaction".to_string())
    })?;

    const UPSERT_CHUNK_SIZE: usize = 400;
    for chunk in mods.chunks(UPSERT_CHUNK_SIZE) {
        let mut qb: QueryBuilder<Postgres> = QueryBuilder::new(
            r#"
            INSERT INTO normalized_mods (
                id, store_id, title, images, price, vendor, product_type, tags, product_url, search_text, search_compact, updated_at
            )
            "#,
        );

        qb.push_values(chunk, |mut row, item| {
            let search_text = build_search_text(item);
            let search_compact = search_text.replace(' ', "");

            row.push_bind(&item.id)
                .push_bind(&item.store_id)
                .push_bind(&item.title)
                .push_bind(SqlJson(&item.images))
                .push_bind(item.price)
                .push_bind(&item.vendor)
                .push_bind(&item.product_type)
                .push_bind(SqlJson(&item.tags))
                .push_bind(&item.product_url)
                .push_bind(search_text)
                .push_bind(search_compact)
                .push("NOW()");
        });

        qb.push(
            r#"
            ON CONFLICT (id) DO UPDATE SET
                store_id = EXCLUDED.store_id,
                title = EXCLUDED.title,
                images = EXCLUDED.images,
                price = EXCLUDED.price,
                vendor = EXCLUDED.vendor,
                product_type = EXCLUDED.product_type,
                tags = EXCLUDED.tags,
                product_url = EXCLUDED.product_url,
                search_text = EXCLUDED.search_text,
                search_compact = EXCLUDED.search_compact,
                updated_at = NOW()
            "#,
        );

        qb.build()
            .execute(&mut *tx)
            .await
            .map_err(|error| {
                error!("database upsert failed: {error}");
                AppError::Database("failed to upsert products".to_string())
            })?;
    }

    if mods.is_empty() {
        sqlx::query("DELETE FROM normalized_mods WHERE store_id = $1")
            .bind(store_id)
            .execute(&mut *tx)
            .await
            .map_err(|error| {
                error!("database cleanup failed: {error}");
                AppError::Database("failed to prune products".to_string())
            })?;
    } else {
        // All rows upserted in this transaction have updated_at set to NOW(),
        // which is stable for the lifetime of the transaction. This lets us prune
        // removed products without sending a huge id array to Postgres.
        sqlx::query("DELETE FROM normalized_mods WHERE store_id = $1 AND updated_at < NOW()")
            .bind(store_id)
            .execute(&mut *tx)
            .await
            .map_err(|error| {
                error!("database cleanup failed: {error}");
                AppError::Database("failed to prune products".to_string())
            })?;
    }

    tx.commit().await.map_err(|error| {
        error!("database transaction commit failed: {error}");
        AppError::Database("failed to commit transaction".to_string())
    })?;

    Ok(())
}

fn build_search_text(item: &NormalizedMod) -> String {
    let mut parts = Vec::with_capacity(item.tags.len() + 3);

    for source in [
        item.title.as_str(),
        item.vendor.as_str(),
        item.product_type.as_str(),
    ] {
        let normalized = normalize_match_text(source);
        if !normalized.is_empty() {
            parts.push(normalized);
        }
    }

    parts.extend(
        item.tags
            .iter()
            .map(|tag| normalize_match_text(tag))
            .filter(|tag| !tag.is_empty()),
    );

    parts.join(" ")
}

fn default_stores() -> Vec<Store> {
    vec![
        Store {
            id: "21overlays".to_string(),
            name: "21 Overlays".to_string(),
            base_url: "https://21overlays.com.au".to_string(),
            logo_url: None,
        },
        Store {
            id: "dubhaus".to_string(),
            name: "Dubhaus".to_string(),
            base_url: "https://dubhaus.com.au".to_string(),
            logo_url: Some("https://dubhaus.com.au/cdn/shop/files/Dubhaus-Logo-Dark_2x_aceaf8af-66d7-4aa4-9bdc-e7b868f4752b.png?v=1677123947&width=2000".to_string()),
        },
        Store {
            id: "modeautoconcepts".to_string(),
            name: "Mode Auto Concepts".to_string(),
            base_url: "https://modeautoconcepts.com".to_string(),
            logo_url: Some("https://modeautoconcepts.com/cdn/shop/files/mode_website_header.png?v=1726554561&width=130".to_string()),
        },
        Store {
            id: "xforce".to_string(),
            name: "XForce".to_string(),
            base_url: "https://xforce.com.au".to_string(),
            logo_url: Some("https://xforce.com.au/cdn/shop/files/Logo_Square_X_RED.png?v=1754529662".to_string()),
        },
        Store {
            id: "justjap".to_string(),
            name: "JustJap".to_string(),
            base_url: "https://justjap.com".to_string(),
            logo_url: Some("https://justjap.com/cdn/shop/t/76/assets/icon-logo.svg?v=158336173239139661481733262283".to_string()),
        },
        Store {
            id: "modsdirect".to_string(),
            name: "Mods Direct".to_string(),
            base_url: "https://www.modsdirect.com.au".to_string(),
            logo_url: Some("https://www.modsdirect.com.au/cdn/shop/files/MODSPPFBLK.png?v=1717205712&width=520".to_string()),
        },
        Store {
            id: "prospeedracing".to_string(),
            name: "Prospeed Racing".to_string(),
            base_url: "https://www.prospeedracing.com.au".to_string(),
            logo_url: Some("https://www.prospeedracing.com.au/cdn/shop/files/pro_speed_racing_logo.png?v=1702293418&width=340".to_string()),
        },
        Store {
            id: "shiftymods".to_string(),
            name: "Shifty Mods".to_string(),
            base_url: "https://shiftymods.com.au".to_string(),
            logo_url: Some("https://shiftymods.com.au/cdn/shop/files/3.png?v=1724340298&width=275".to_string()),
        },
        Store {
            id: "hi-torqueperformance".to_string(),
            name: "Hi-Torque Performance".to_string(),
            base_url: "https://hi-torqueperformance.myshopify.com".to_string(),
            logo_url: Some("https://hi-torqueperformance.myshopify.com/cdn/shop/files/HTP_logo_300x300.png?v=1751503487".to_string()),
        },
        Store {
            id: "performancewarehouse".to_string(),
            name: "Performance Warehouse".to_string(),
            base_url: "https://performancewarehouse.com.au".to_string(),
            logo_url: Some("https://cdn.shopify.com/s/files/1/0323/1596/5572/files/main-logo-v4.png?v=1707862321".to_string()),
        },
        Store {
            id: "streetelement".to_string(),
            name: "Street Element".to_string(),
            base_url: "https://streetelement.com.au".to_string(),
            logo_url: None,
        },
        Store {
            id: "allautomotiveparts".to_string(),
            name: "All Automotive Parts".to_string(),
            base_url: "https://allautomotiveparts.com.au".to_string(),
            logo_url: Some("https://allautomotiveparts.com.au/cdn/shop/files/logo_3.png?v=1662423972&width=438".to_string()),
        },
        Store {
            id: "eziautoparts".to_string(),
            name: "Ezi Auto Parts".to_string(),
            base_url: "https://eziautoparts.com.au".to_string(),
            logo_url: Some("https://eziautoparts.com.au/cdn/shop/files/eziauto_logo_white_inlay.png?v=1711271402&width=600".to_string()),
        },
        Store {
            id: "autocave".to_string(),
            name: "Auto Cave".to_string(),
            base_url: "https://autocave.com.au".to_string(),
            logo_url: Some("https://autocave.com.au/cdn/shop/files/Untitled_design_-_2024-12-09T203629.178_300x@2x.png?v=1733736998".to_string()),
        },
        Store {
            id: "jtmauto".to_string(),
            name: "JTM Auto".to_string(),
            base_url: "https://jtmauto.com.au".to_string(),
            logo_url: Some("https://jtmauto.com.au/cdn/shop/files/jtm-logo4_456x60.png?v=1704599783".to_string()),
        },
        Store {
            id: "tjautoparts".to_string(),
            name: "TJ Auto Parts".to_string(),
            base_url: "https://tjautoparts.com.au".to_string(),
            logo_url: Some("https://tjautoparts.com.au/cdn/shop/files/Logo-01_Crop_393x150.png?v=1711854530".to_string()),
        },
        Store {
            id: "nationwideautoparts".to_string(),
            name: "Nationwide Auto Parts".to_string(),
            base_url: "https://www.nationwideautoparts.com.au".to_string(),
            logo_url: Some("https://www.nationwideautoparts.com.au/cdn/shop/files/NW-Logo-Temp_200x50.png?v=1745620530".to_string()),
        },
        Store {
            id: "chicaneaustralia".to_string(),
            name: "Chicane Australia".to_string(),
            base_url: "https://www.chicaneaustralia.com.au".to_string(),
            logo_url: Some("https://www.chicaneaustralia.com.au/cdn/shop/files/ChicaneLogo_2048x2048-LockupWhiteTransparent_V1.png?v=1747808484&width=300".to_string()),
        },
    ]
}
