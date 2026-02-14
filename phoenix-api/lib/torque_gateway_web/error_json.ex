defmodule TorqueGatewayWeb.ErrorJSON do
  def render("404.json", _assigns), do: %{error: %{code: "NOT_FOUND", message: "Not found"}}
  def render("500.json", _assigns), do: %{error: %{code: "INTERNAL_ERROR", message: "Internal server error"}}
end
