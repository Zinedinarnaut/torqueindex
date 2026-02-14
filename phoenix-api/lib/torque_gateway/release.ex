defmodule TorqueGateway.Release do
  @moduledoc false

  @app :torque_gateway

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, migrations_path(repo), :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, migrations_path(repo), :down, to: version)
      end)
  end

  defp migrations_path(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    priv_dir = :code.priv_dir(app)
    Path.join([priv_dir, "repo", "migrations"])
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
