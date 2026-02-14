import Config

rust_service_url = System.get_env("RUST_SERVICE_URL", "http://localhost:3001")
cache_ttl_ms = System.get_env("CACHE_TTL_MS", "60000") |> String.to_integer()

config :torque_gateway, :rust_service, base_url: rust_service_url
config :torque_gateway, :cache_ttl_ms, cache_ttl_ms

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Example:
        postgres://USER:PASS@HOST:5432/DBNAME
      """

  pool_size = String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :torque_gateway, TorqueGateway.Repo,
    url: database_url,
    pool_size: pool_size,
    ssl: false

  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      environment variable JWT_SECRET is missing.
      Generate one with: mix phx.gen.secret
      """

  access_ttl = System.get_env("ACCESS_TOKEN_TTL_SECS", "3600") |> String.to_integer()
  refresh_ttl_days = System.get_env("REFRESH_TOKEN_TTL_DAYS", "30") |> String.to_integer()
  reset_ttl_secs = System.get_env("RESET_TOKEN_TTL_SECS", "3600") |> String.to_integer()

  config :torque_gateway,
    jwt_secret: jwt_secret,
    access_token_ttl_secs: access_ttl,
    refresh_token_ttl_secs: refresh_ttl_days * 24 * 60 * 60,
    reset_token_ttl_secs: reset_ttl_secs,
    password_reset_url_base: System.get_env("PASSWORD_RESET_URL_BASE", "torqueindex://reset?token=")
end

case System.get_env("STORE_REGISTRY_JSON") do
  nil ->
    :ok

  raw_json ->
    case Jason.decode(raw_json) do
      {:ok, stores} when is_list(stores) ->
        normalized =
          Enum.map(stores, fn store ->
            logo_url =
              case Map.get(store, "logo_url") do
                nil -> nil
                "" -> nil
                value -> to_string(value)
              end

            %{
              id: to_string(Map.get(store, "id", "")),
              name: to_string(Map.get(store, "name", "")),
              base_url: to_string(Map.get(store, "base_url", "")),
              logo_url: logo_url
            }
          end)

        config :torque_gateway, :store_registry, normalized

      _ ->
        IO.warn("Ignoring invalid STORE_REGISTRY_JSON value")
    end
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :torque_gateway, TorqueGatewayWeb.Endpoint,
    url: [host: host, port: 80, scheme: "http"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
