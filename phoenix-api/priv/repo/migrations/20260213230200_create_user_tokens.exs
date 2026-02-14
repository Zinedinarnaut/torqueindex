defmodule TorqueGateway.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    create table(:user_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :context, :text, null: false
      add :sent_to, :text
      add :token_hash, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec

      timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
    end

    create index(:user_tokens, [:user_id])
    create index(:user_tokens, [:context])
    create unique_index(:user_tokens, [:token_hash])
  end
end

