defmodule TorqueGateway.RustClient do
  alias TorqueGateway.Error

  @spec get_stores() :: {:ok, list(map())} | {:error, Error.t()}
  def get_stores do
    with {:ok, body} <- get_json("/internal/stores", %{}),
         %{"data" => stores} when is_list(stores) <- body do
      {:ok, stores}
    else
      {:ok, _unexpected_body} -> {:error, Error.upstream_error("Rust service returned invalid stores payload")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec get_mods(map()) :: {:ok, list(map())} | {:error, Error.t()}
  def get_mods(filters) when is_map(filters) do
    with {:ok, body} <- get_json("/internal/mods", filters),
         %{"data" => mods} when is_list(mods) <- body do
      {:ok, mods}
    else
      {:ok, _unexpected_body} -> {:error, Error.upstream_error("Rust service returned invalid mods payload")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec get_mod(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_mod(id) when is_binary(id) do
    with {:ok, body} <- get_json("/internal/mods/#{id}", %{}),
         %{"data" => mod} when is_map(mod) <- body do
      {:ok, mod}
    else
      {:ok, _unexpected_body} -> {:error, Error.upstream_error("Rust service returned invalid mod payload")}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp get_json(path, params) do
    request =
      Req.new(
        base_url: base_url(),
        url: path,
        finch: TorqueGatewayFinch,
        receive_timeout: 20_000,
        retry: :transient
      )

    case Req.get(request, params: params) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, map_status(status, message)}

      {:ok, %Req.Response{status: status}} ->
        {:error, map_status(status, "Rust service returned HTTP #{status}")}

      {:error, exception} ->
        {:error, Error.upstream_error("Rust service request failed: #{Exception.message(exception)}")}
    end
  end

  defp base_url do
    Application.get_env(:torque_gateway, :rust_service, [])
    |> Keyword.get(:base_url, "http://localhost:3001")
  end

  defp map_status(status, message) when status in [400, 422], do: Error.bad_request(message)
  defp map_status(404, message), do: Error.not_found(message)
  defp map_status(status, message) when status in [502, 503, 504], do: Error.upstream_error(message)
  defp map_status(_status, message), do: Error.internal_error(message)
end
