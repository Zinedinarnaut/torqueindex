import Config

config :logger, level: :warning

database_url =
  System.get_env(
    "DATABASE_URL",
    "postgres://postgres:postgres@localhost:5432/torque_gateway_test"
  )

config :torque_gateway, TorqueGateway.Repo,
  url: database_url,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  ssl: false

config :torque_gateway,
  jwt_secret: "torque_gateway_test_jwt_secret",
  password_reset_url_base: "https://example.invalid/reset?token="

config :torque_gateway, TorqueGatewayWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "torque_gateway_test_secret_key_base"
