defmodule TorqueGateway.Cache do
  use GenServer

  @table :torque_gateway_cache
  @cleanup_interval_ms 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(key) do
    now = now_ms()

    case :ets.lookup(@table, key) do
      [{^key, expires_at, value}] when expires_at > now -> {:ok, value}
      [{^key, _expires_at, _value}] ->
        :ets.delete(@table, key)
        :miss

      [] ->
        :miss
    end
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    expires_at = now_ms() + ttl_ms
    true = :ets.insert(@table, {key, expires_at, value})
    :ok
  end

  @impl true
  def init(state) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = now_ms()

    :ets.foldl(
      fn {key, expires_at, _value}, _acc ->
        if expires_at <= now do
          :ets.delete(@table, key)
        end

        :ok
      end,
      :ok,
      @table
    )

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
