defmodule TorqueGateway.RateLimiter do
  use GenServer

  @table :torque_gateway_rate_limiter
  @cleanup_interval_ms 60_000

  @type key :: term()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec hit(key(), pos_integer(), pos_integer()) ::
          :ok | {:error, %{retry_after_secs: non_neg_integer()}}
  def hit(key, limit, window_secs)
      when is_integer(limit) and limit > 0 and is_integer(window_secs) and window_secs > 0 do
    now_ms = now_ms()
    window_ms = window_secs * 1000

    case :ets.lookup(@table, key) do
      [{^key, count, reset_at_ms}] when reset_at_ms > now_ms ->
        if count + 1 <= limit do
          true = :ets.insert(@table, {key, count + 1, reset_at_ms})
          :ok
        else
          retry_after_secs = max(div(reset_at_ms - now_ms + 999, 1000), 0)
          {:error, %{retry_after_secs: retry_after_secs}}
        end

      _ ->
        reset_at_ms = now_ms + window_ms
        true = :ets.insert(@table, {key, 1, reset_at_ms})
        :ok
    end
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
      fn {key, _count, reset_at_ms}, _acc ->
        if reset_at_ms <= now do
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

