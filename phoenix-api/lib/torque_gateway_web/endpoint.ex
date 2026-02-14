defmodule TorqueGatewayWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :torque_gateway

  socket "/socket", TorqueGatewayWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :torque_gateway,
    gzip: false,
    only: ~w(store_logos)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug TorqueGatewayWeb.Router
end
