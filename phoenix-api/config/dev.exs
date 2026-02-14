import Config

database_url =
  System.get_env(
    "DATABASE_URL",
    "postgres://postgres:postgres@localhost:5432/torqueindex_dev?sslmode=disable"
  )

config :torque_gateway, TorqueGateway.Repo,
  url: database_url,
  pool_size: 10,
  ssl: false

config :torque_gateway,
  jwt_secret: System.get_env("JWT_SECRET", "dev_jwt_secret_change_me"),
  log_password_reset_tokens: true

config :torque_gateway, TorqueGatewayWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base: "torque_gateway_dev_secret_key_base_please_change_in_prod",
  server: true,
  watchers: []

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
