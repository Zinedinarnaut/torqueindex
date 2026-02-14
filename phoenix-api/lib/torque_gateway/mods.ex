defmodule TorqueGateway.Mods do
  alias TorqueGateway.{Cache, Error, RustClient, StoreRegistry}

  @spec list_stores() :: {:ok, list(map())} | {:error, Error.t()}
  def list_stores do
    with {:ok, stores} <- RustClient.get_stores() do
      enriched =
        stores
        |> StoreRegistry.filter_stores()
        |> StoreRegistry.enrich_stores()

      {:ok, enriched}
    end
  end

  @spec list_mods(map()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_mods(filters) when is_map(filters) do
    sanitized = sanitize_filters(filters)

    if Enum.all?([sanitized.make, sanitized.model, sanitized.engine], &is_nil/1) do
      {:error, Error.bad_request("At least one filter is required: make, model, or engine")}
    else
      cache_key = {:mods, sanitized.make, sanitized.model, sanitized.engine}

      case Cache.get(cache_key) do
        {:ok, mods} -> {:ok, mods}
        :miss -> fetch_and_cache_mods(cache_key, sanitized)
      end
    end
  end

  @spec get_mod(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_mod(id) when is_binary(id) do
    cache_key = {:mod, id}

    case Cache.get(cache_key) do
      {:ok, mod} -> {:ok, mod}
      :miss ->
        with {:ok, mod} <- RustClient.get_mod(id),
             true <- StoreRegistry.store_enabled?(mod["store_id"]) do
          Cache.put(cache_key, mod, cache_ttl_ms())
          {:ok, mod}
        else
          false -> {:error, Error.not_found("Mod #{id} was not found")}
          {:error, %Error{} = error} -> {:error, error}
        end
    end
  end

  defp fetch_and_cache_mods(cache_key, sanitized) do
    rust_filters = %{
      "make" => Map.get(sanitized, :make),
      "model" => Map.get(sanitized, :model),
      "engine" => Map.get(sanitized, :engine)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    with {:ok, mods} <- RustClient.get_mods(rust_filters) do
      filtered = StoreRegistry.filter_mods(mods)
      Cache.put(cache_key, filtered, cache_ttl_ms())
      {:ok, filtered}
    end
  end

  defp sanitize_filters(filters) do
    make = read_filter(filters, "make")
    model = read_filter(filters, "model")
    engine = read_filter(filters, "engine")

    %{make: make, model: model, engine: engine}
  end

  defp read_filter(filters, key) do
    value =
      case key do
        "make" -> Map.get(filters, "make") || Map.get(filters, :make)
        "model" -> Map.get(filters, "model") || Map.get(filters, :model)
        "engine" -> Map.get(filters, "engine") || Map.get(filters, :engine)
      end

    case value do
      nil -> nil
      "" -> nil
      binary when is_binary(binary) -> String.trim(binary)
      other -> to_string(other)
    end
  end

  defp cache_ttl_ms do
    Application.get_env(:torque_gateway, :cache_ttl_ms, 60_000)
  end
end
