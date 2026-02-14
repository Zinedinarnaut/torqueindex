defmodule TorqueGatewayWeb.FallbackController do
  use TorqueGatewayWeb, :controller
  alias TorqueGateway.Error

  def call(conn, {:error, %Error{} = error}) do
    conn
    |> put_status(error.status)
    |> json(%{error: %{code: error.code, message: error.message}})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: %{code: "INTERNAL_ERROR", message: inspect(reason)}})
  end
end
