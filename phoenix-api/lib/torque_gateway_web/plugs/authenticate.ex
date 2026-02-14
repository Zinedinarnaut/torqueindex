defmodule TorqueGatewayWeb.Plugs.Authenticate do
  import Plug.Conn

  alias TorqueGateway.{Accounts, Auth, Error}

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- read_bearer(conn),
         {:ok, claims} <- Auth.verify_access_token(token),
         %{"sub" => user_id} <- claims,
         {:ok, user} <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      {:error, %Error{} = error} -> reject(conn, error)
      {:error, _reason} -> reject(conn, Error.unauthorized("Invalid access token"))
      _ -> reject(conn, Error.unauthorized("Authentication required"))
    end
  end

  defp read_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      ["bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :missing}
    end
  end

  defp reject(conn, %Error{} = error) do
    body = Jason.encode!(%{error: %{code: error.code, message: error.message}})

    conn
    |> put_resp_content_type("application/json")
    |> put_status(error.status)
    |> send_resp(error.status, body)
    |> halt()
  end
end

