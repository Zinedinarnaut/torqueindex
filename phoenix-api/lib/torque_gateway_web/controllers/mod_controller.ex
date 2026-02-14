defmodule TorqueGatewayWeb.ModController do
  use TorqueGatewayWeb, :controller

  alias TorqueGateway.Mods

  action_fallback TorqueGatewayWeb.FallbackController

  def index(conn, params) do
    filters =
      params
      |> Map.take(["make", "model", "engine"])

    with {:ok, mods} <- Mods.list_mods(filters) do
      json(conn, %{data: mods, meta: %{count: length(mods)}})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, mod} <- Mods.get_mod(id) do
      json(conn, %{data: mod})
    end
  end
end
