defmodule TorqueGateway.Repo.Migrations.EnablePgcryptoAndCreateUsers do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :text, null: false
      add :username, :text, null: false
      add :password_hash, :text, null: false
      add :verified, :boolean, null: false, default: false

      # Optional single-session legacy field. The canonical refresh token store lives
      # in refresh_tokens for multi-device support + rotation.
      add :refresh_token_hash, :text

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
  end
end

