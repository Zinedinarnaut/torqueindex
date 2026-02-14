defmodule TorqueGateway.Accounts.RefreshToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}

  schema "refresh_tokens" do
    field :token_hash, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :replaced_by_token_hash, :string, redact: true
    field :ip, :string
    field :user_agent, :string

    belongs_to :user, TorqueGateway.Accounts.User

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :expires_at, :revoked_at, :replaced_by_token_hash, :ip, :user_agent])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
