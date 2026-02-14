defmodule TorqueGatewayWeb.Plugs.LoginThrottle do
  import Plug.Conn

  alias TorqueGateway.{Error, RateLimiter}

  # Reasonable defaults for password-guessing protection.
  @limit 8
  @window_secs 600

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = remote_ip(conn)
    email = read_email(conn)
    key = {:signin, ip, email}

    case RateLimiter.hit(key, @limit, @window_secs) do
      :ok ->
        conn

      {:error, %{retry_after_secs: retry_after_secs}} ->
        error = Error.too_many_requests("Too many login attempts. Try again later.")
        body = Jason.encode!(%{error: %{code: error.code, message: error.message}})

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_secs))
        |> put_resp_content_type("application/json")
        |> put_status(error.status)
        |> send_resp(error.status, body)
        |> halt()
    end
  end

  defp remote_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> "unknown"
  end

  defp read_email(conn) do
    params = conn.body_params || %{}

    value =
      Map.get(params, "email") ||
        Map.get(params, :email) ||
        ""

    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end

