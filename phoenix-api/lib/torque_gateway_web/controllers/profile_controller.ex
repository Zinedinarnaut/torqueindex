defmodule TorqueGatewayWeb.ProfileController do
  use TorqueGatewayWeb, :controller

  alias TorqueGateway.{Accounts, Error}

  action_fallback TorqueGatewayWeb.FallbackController

  def me(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        {:error, Error.unauthorized("Authentication required")}

      user ->
        json(conn, %{data: Accounts.public_profile(user)})
    end
  end

  def update_me(conn, params) do
    case conn.assigns[:current_user] do
      nil ->
        {:error, Error.unauthorized("Authentication required")}

      user ->
        attrs =
          params
          |> Map.take(["email", "username"])

        if map_size(attrs) == 0 do
          {:error, Error.bad_request("No updatable fields provided")}
        else
        with {:ok, updated} <- Accounts.update_profile(user, attrs) do
          json(conn, %{data: Accounts.public_profile(updated)})
        end
        end
    end
  end
end
