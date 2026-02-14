defmodule TorqueGateway.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}

  schema "user_tokens" do
    field :context, :string
    field :sent_to, :string
    field :token_hash, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec

    belongs_to :user, TorqueGateway.Accounts.User

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :context, :sent_to, :token_hash, :expires_at, :used_at])
    |> validate_required([:user_id, :context, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
