defmodule TorqueGateway.StoreRegistry do
  @spec all() :: list(map())
  def all do
    Application.get_env(:torque_gateway, :store_registry, [])
    |> Enum.map(&normalize_store/1)
  end

  @spec enabled_ids() :: MapSet.t(String.t())
  def enabled_ids do
    all()
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  @spec filter_stores(list(map())) :: list(map())
  def filter_stores(stores) when is_list(stores) do
    ids = enabled_ids()

    if MapSet.size(ids) == 0 do
      stores
    else
      Enum.filter(stores, fn store -> MapSet.member?(ids, store["id"] || store[:id]) end)
    end
  end

  @spec filter_mods(list(map())) :: list(map())
  def filter_mods(mods) when is_list(mods) do
    ids = enabled_ids()

    if MapSet.size(ids) == 0 do
      mods
    else
      Enum.filter(mods, fn mod -> MapSet.member?(ids, mod["store_id"] || mod[:store_id]) end)
    end
  end

  @spec store_enabled?(String.t()) :: boolean()
  def store_enabled?(store_id) when is_binary(store_id) do
    ids = enabled_ids()
    MapSet.size(ids) == 0 or MapSet.member?(ids, store_id)
  end

  @spec metadata_by_id() :: map()
  def metadata_by_id do
    all()
    |> Enum.reduce(%{}, fn store, acc -> Map.put(acc, store.id, store) end)
  end

  @spec enrich_stores(list(map())) :: list(map())
  def enrich_stores(stores) when is_list(stores) do
    meta = metadata_by_id()

    Enum.map(stores, fn store ->
      id = store["id"] || store[:id] || ""

      case Map.get(meta, id) do
        %{logo_url: logo_url} when is_binary(logo_url) and logo_url != "" ->
          Map.put(store, "logo_url", logo_url)

        _ ->
          store
      end
    end)
  end

  defp normalize_store(store) when is_map(store) do
    %{
      id: store[:id] || store["id"] || "",
      name: store[:name] || store["name"] || "",
      base_url: store[:base_url] || store["base_url"] || "",
      logo_url: store[:logo_url] || store["logo_url"] || nil
    }
  end
end
