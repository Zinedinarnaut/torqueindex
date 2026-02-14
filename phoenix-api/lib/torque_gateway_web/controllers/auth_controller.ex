defmodule TorqueGatewayWeb.AuthController do
  use TorqueGatewayWeb, :controller

  alias TorqueGateway.{Accounts, Error}

  plug TorqueGatewayWeb.Plugs.LoginThrottle when action in [:signin]

  action_fallback TorqueGatewayWeb.FallbackController

  def signup(conn, params) do
    attrs = %{
      "email" => Map.get(params, "email"),
      "username" => Map.get(params, "username"),
      "password" => Map.get(params, "password")
    }

    with {:ok, user} <- Accounts.register_user(attrs),
         {:ok, %{access_token: access_token, refresh_token: refresh_token}} <-
           Accounts.issue_session(user, request_meta(conn)) do
      json(conn, %{
        access_token: access_token,
        refresh_token: refresh_token,
        profile: Accounts.public_profile(user)
      })
    end
  end

  def signin(conn, params) do
    email = Map.get(params, "email") || ""
    password = Map.get(params, "password") || ""

    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, %{access_token: access_token, refresh_token: refresh_token}} <-
           Accounts.issue_session(user, request_meta(conn)) do
      json(conn, %{
        access_token: access_token,
        refresh_token: refresh_token,
        profile: Accounts.public_profile(user)
      })
    end
  end

  def refresh(conn, params) do
    refresh_token = Map.get(params, "refresh_token") || ""

    with {:ok, %{access_token: access_token, refresh_token: new_refresh, user: user}} <-
           Accounts.refresh_session(refresh_token, request_meta(conn)) do
      json(conn, %{
        access_token: access_token,
        refresh_token: new_refresh,
        profile: Accounts.public_profile(user)
      })
    end
  end

  def signout(conn, params) do
    user = conn.assigns[:current_user]
    refresh_token = Map.get(params, "refresh_token")

    cond do
      is_map(user) and is_binary(refresh_token) and refresh_token != "" ->
        :ok = Accounts.revoke_refresh_token(refresh_token)
        json(conn, %{data: "ok"})

      is_map(user) ->
        :ok = Accounts.revoke_all_sessions(user.id)
        json(conn, %{data: "ok"})

      true ->
        {:error, Error.unauthorized("Authentication required")}
    end
  end

  def reset_request(conn, params) do
    email = Map.get(params, "email") || ""
    :ok = Accounts.request_password_reset(to_string(email))
    json(conn, %{data: "ok"})
  end

  def reset_confirm(conn, params) do
    token = Map.get(params, "token") || ""
    password = Map.get(params, "password") || ""

    with {:ok, _user} <- Accounts.reset_password(to_string(token), to_string(password)) do
      json(conn, %{data: "ok"})
    end
  end

  defp request_meta(conn) do
    %{
      ip: remote_ip(conn),
      user_agent: user_agent(conn)
    }
  end

  defp remote_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> "unknown"
  end

  defp user_agent(conn) do
    get_req_header(conn, "user-agent")
    |> List.first()
    |> case do
      nil -> nil
      ua -> String.slice(ua, 0, 500)
    end
  end
end

