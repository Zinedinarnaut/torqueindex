defmodule TorqueGateway.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TorqueGateway.Repo,
      {Phoenix.PubSub, name: TorqueGateway.PubSub},
      TorqueGateway.Cache,
      TorqueGateway.RateLimiter,
      {Finch, name: TorqueGatewayFinch},
      TorqueGatewayWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TorqueGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TorqueGatewayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
