defmodule TorqueGateway.Auth.AccessToken do
  use Joken.Config

  @impl true
  def token_config do
    Joken.Config.default_claims(
      iss: issuer(),
      default_exp: access_ttl(),
      skip: [:aud, :jti, :nbf]
    )
    |> add_claim("typ", fn -> "access" end, fn value, _claims -> value == "access" end)
  end

  defp issuer do
    Application.get_env(:torque_gateway, :jwt_issuer, "torque_gateway")
  end

  defp access_ttl do
    Application.get_env(:torque_gateway, :access_token_ttl_secs, 3600)
  end
end

