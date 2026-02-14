defmodule TorqueGateway.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :verified, :boolean, default: false
    field :refresh_token_hash, :string, redact: true

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime_usec)
  end

  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  @username_regex ~r/^[a-zA-Z0-9_]+$/

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :username, :password])
    |> validate_required([:email, :username, :password])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:username, &normalize_username/1)
    |> validate_format(:email, @email_regex)
    |> validate_length(:email, max: 320)
    |> validate_format(:username, @username_regex)
    |> validate_length(:username, min: 3, max: 24)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> put_password_hash()
  end

  def update_profile_changeset(user, attrs) do
    changeset =
      user
      |> cast(attrs, [:email, :username])
      |> update_change(:email, &normalize_email/1)
      |> update_change(:username, &normalize_username/1)

    required =
      []
      |> maybe_require(changeset, :email)
      |> maybe_require(changeset, :username)

    changeset
    |> validate_required(required)
    |> validate_format(:email, @email_regex)
    |> validate_length(:email, max: 320)
    |> validate_format(:username, @username_regex)
    |> validate_length(:username, min: 3, max: 24)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> maybe_mark_unverified()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> put_password_hash()
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_username(nil), do: nil
  defp normalize_username(username) when is_binary(username), do: String.trim(username)

  defp maybe_require(required, changeset, field) do
    if Map.has_key?(changeset.changes, field) do
      [field | required]
    else
      required
    end
  end

  defp put_password_hash(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
    end
  end

  defp maybe_mark_unverified(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      _new_email -> put_change(changeset, :verified, false)
    end
  end
end
