defmodule TorqueGatewayWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      alias TorqueGateway.Repo

      @endpoint TorqueGatewayWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TorqueGateway.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TorqueGateway.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

