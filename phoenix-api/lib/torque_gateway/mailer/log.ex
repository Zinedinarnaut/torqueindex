defmodule TorqueGateway.Mailer.Log do
  @behaviour TorqueGateway.Mailer

  require Logger

  @impl true
  def deliver_password_reset_instructions(email, reset_url) do
    if Application.get_env(:torque_gateway, :log_password_reset_tokens, false) do
      Logger.info("password reset requested for #{email}: #{reset_url}")
    else
      Logger.info("password reset requested for #{email}")
    end

    :ok
  end
end
