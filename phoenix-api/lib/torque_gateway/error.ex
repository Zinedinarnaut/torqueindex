defmodule TorqueGateway.Error do
  @enforce_keys [:status, :code, :message]
  defexception [:status, :code, :message]

  @type t :: %__MODULE__{status: pos_integer(), code: String.t(), message: String.t()}

  def bad_request(message), do: %__MODULE__{status: 400, code: "BAD_REQUEST", message: message}
  def unauthorized(message), do: %__MODULE__{status: 401, code: "UNAUTHORIZED", message: message}
  def forbidden(message), do: %__MODULE__{status: 403, code: "FORBIDDEN", message: message}
  def not_found(message), do: %__MODULE__{status: 404, code: "NOT_FOUND", message: message}
  def too_many_requests(message), do: %__MODULE__{status: 429, code: "RATE_LIMITED", message: message}
  def upstream_error(message), do: %__MODULE__{status: 502, code: "UPSTREAM_ERROR", message: message}
  def internal_error(message), do: %__MODULE__{status: 500, code: "INTERNAL_ERROR", message: message}
end
