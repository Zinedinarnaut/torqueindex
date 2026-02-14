defmodule TorqueGatewayWeb.StoreController do
  use TorqueGatewayWeb, :controller

  alias TorqueGateway.Mods

  action_fallback TorqueGatewayWeb.FallbackController

  def index(conn, _params) do
    with {:ok, stores} <- Mods.list_stores() do
      json(conn, %{data: normalize_logos(conn, stores)})
    end
  end

  defp normalize_logos(conn, stores) when is_list(stores) do
    Enum.map(stores, &normalize_logo(conn, &1))
  end

  defp normalize_logo(conn, store) when is_map(store) do
    logo_url = store["logo_url"] || store[:logo_url]

    cond do
      is_binary(logo_url) and String.starts_with?(logo_url, "/") ->
        Map.put(store, "logo_url", absolute_url(conn, logo_url))

      true ->
        store
    end
  end

  defp absolute_url(conn, path) do
    scheme = Atom.to_string(conn.scheme)
    host = conn.host
    port = conn.port

    base =
      cond do
        scheme == "http" and port == 80 -> "#{scheme}://#{host}"
        scheme == "https" and port == 443 -> "#{scheme}://#{host}"
        true -> "#{scheme}://#{host}:#{port}"
      end

    base <> path
  end
end
