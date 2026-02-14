defmodule TorqueGateway.Mailer do
  @moduledoc false

  @callback deliver_password_reset_instructions(email :: String.t(), reset_url :: String.t()) :: :ok | {:error, term()}

  def impl do
    Application.get_env(:torque_gateway, :mailer, TorqueGateway.Mailer.Log)
  end

  def deliver_password_reset_instructions(email, reset_url) do
    impl().deliver_password_reset_instructions(email, reset_url)
  end
end

