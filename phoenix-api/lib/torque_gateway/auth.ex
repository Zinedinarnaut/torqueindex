defmodule TorqueGateway.Auth do
  @moduledoc false

  alias TorqueGateway.Auth.AccessToken

  @access_typ "access"

  def access_token_ttl_secs do
    Application.get_env(:torque_gateway, :access_token_ttl_secs, 3600)
  end

  def refresh_token_ttl_secs do
    Application.get_env(:torque_gateway, :refresh_token_ttl_secs, 60 * 60 * 24 * 30)
  end

  def reset_token_ttl_secs do
    Application.get_env(:torque_gateway, :reset_token_ttl_secs, 60 * 60)
  end

  def password_reset_url_base do
    Application.get_env(:torque_gateway, :password_reset_url_base, "torqueindex://reset?token=")
  end

  defp signer do
    secret = Application.get_env(:torque_gateway, :jwt_secret, "dev_jwt_secret_change_me")
    Joken.Signer.create("HS256", secret)
  end

  @spec issue_access_token(binary()) :: {:ok, String.t()} | {:error, term()}
  def issue_access_token(user_id) when is_binary(user_id) do
    {:ok, token, _claims} =
      AccessToken.generate_and_sign(%{"sub" => user_id, "typ" => @access_typ}, signer())

    {:ok, token}
  rescue
    error -> {:error, error}
  end

  @spec verify_access_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_access_token(token) when is_binary(token) do
    AccessToken.verify_and_validate(token, signer())
  end

  @spec generate_refresh_token() :: String.t()
  def generate_refresh_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @spec generate_user_token() :: String.t()
  def generate_user_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @spec token_hash(String.t()) :: String.t()
  def token_hash(raw_token) when is_binary(raw_token) do
    :crypto.hash(:sha256, raw_token)
    |> Base.encode64(padding: false)
  end
end

