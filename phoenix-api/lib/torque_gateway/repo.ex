defmodule TorqueGateway.Repo do
  use Ecto.Repo,
    otp_app: :torque_gateway,
    adapter: Ecto.Adapters.Postgres
end

