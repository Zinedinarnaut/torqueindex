defmodule TorqueGatewayWeb.ModsChannel do
  use TorqueGatewayWeb, :channel

  @impl true
  def join("mods:lobby", _payload, socket) do
    {:ok, %{message: "connected"}, socket}
  end

  def join("mods:" <> _topic, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
