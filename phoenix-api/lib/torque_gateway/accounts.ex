defmodule TorqueGateway.Accounts do
  import Ecto.Query

  alias Ecto.Multi
  alias TorqueGateway.{Auth, Error, Mailer, Repo}
  alias TorqueGateway.Accounts.{RefreshToken, User, UserToken}

  @reset_context "reset_password"

  @spec register_user(map()) :: {:ok, User.t()} | {:error, Error.t()}
  def register_user(attrs) when is_map(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> normalize_changeset_error("Unable to create user")
  end

  @spec authenticate_user(String.t(), String.t()) :: {:ok, User.t()} | {:error, Error.t()}
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    normalized_email = email |> String.trim() |> String.downcase()

    case Repo.get_by(User, email: normalized_email) do
      %User{} = user ->
        if Argon2.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          Argon2.no_user_verify()
          {:error, Error.unauthorized("Invalid email or password")}
        end

      nil ->
        Argon2.no_user_verify()
        {:error, Error.unauthorized("Invalid email or password")}
    end
  end

  @spec issue_session(User.t(), map()) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, Error.t()}
  def issue_session(%User{} = user, meta \\ %{}) do
    with {:ok, access_token} <- Auth.issue_access_token(user.id),
         {:ok, refresh_token} <- create_refresh_token(user, meta) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.internal_error("Failed to issue session: #{inspect(reason)}")}
    end
  end

  @spec refresh_session(String.t(), map()) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t(), user: User.t()}} | {:error, Error.t()}
  def refresh_session(refresh_token, meta \\ %{}) when is_binary(refresh_token) do
    token_hash = Auth.token_hash(refresh_token)
    now = DateTime.utc_now()

    case Repo.get_by(RefreshToken, token_hash: token_hash) do
      nil ->
        {:error, Error.unauthorized("Invalid refresh token")}

      %RefreshToken{} = current ->
        cond do
          not is_nil(current.revoked_at) ->
            message =
              if is_binary(current.replaced_by_token_hash) and current.replaced_by_token_hash != "" do
                "Refresh token has been rotated"
              else
                "Refresh token has been revoked"
              end

            {:error, Error.unauthorized(message)}

          DateTime.compare(current.expires_at, now) != :gt ->
            {:error, Error.unauthorized("Refresh token has expired")}

          true ->
            rotate_refresh_token(current, meta)
        end
    end
  end

  @spec revoke_refresh_token(String.t()) :: :ok
  def revoke_refresh_token(refresh_token) when is_binary(refresh_token) do
    token_hash = Auth.token_hash(refresh_token)
    now = DateTime.utc_now()

    from(t in RefreshToken, where: t.token_hash == ^token_hash and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: now])

    :ok
  end

  @spec revoke_all_sessions(binary()) :: :ok
  def revoke_all_sessions(user_id) when is_binary(user_id) do
    now = DateTime.utc_now()

    from(t in RefreshToken, where: t.user_id == ^user_id and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: now])

    :ok
  end

  @spec get_user(binary()) :: {:ok, User.t()} | {:error, Error.t()}
  def get_user(id) when is_binary(id) do
    case Repo.get(User, id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, Error.not_found("User not found")}
    end
  end

  @spec update_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Error.t()}
  def update_profile(%User{} = user, attrs) when is_map(attrs) do
    user
    |> User.update_profile_changeset(attrs)
    |> Repo.update()
    |> normalize_changeset_error("Unable to update profile")
  end

  @spec request_password_reset(String.t()) :: :ok
  def request_password_reset(email) when is_binary(email) do
    normalized_email = email |> String.trim() |> String.downcase()

    case Repo.get_by(User, email: normalized_email) do
      %User{} = user ->
        token = Auth.generate_user_token()
        token_hash = Auth.token_hash(token)
        expires_at = DateTime.add(DateTime.utc_now(), Auth.reset_token_ttl_secs(), :second)

        %UserToken{}
        |> UserToken.changeset(%{
          user_id: user.id,
          context: @reset_context,
          sent_to: user.email,
          token_hash: token_hash,
          expires_at: expires_at
        })
        |> Repo.insert()

        reset_url = Auth.password_reset_url_base() <> token
        _ = Mailer.deliver_password_reset_instructions(user.email, reset_url)
        :ok

      nil ->
        :ok
    end
  end

  @spec reset_password(String.t(), String.t()) :: {:ok, User.t()} | {:error, Error.t()}
  def reset_password(token, new_password) when is_binary(token) and is_binary(new_password) do
    token_hash = Auth.token_hash(token)
    now = DateTime.utc_now()

    case Repo.get_by(UserToken, token_hash: token_hash, context: @reset_context) do
      nil ->
        {:error, Error.bad_request("Invalid reset token")}

      %UserToken{used_at: %DateTime{}} ->
        {:error, Error.bad_request("Reset token has already been used")}

      %UserToken{} = user_token ->
        if DateTime.compare(user_token.expires_at, now) != :gt do
          {:error, Error.bad_request("Reset token has expired")}
        else
        Repo.transaction(fn ->
          user = Repo.get!(User, user_token.user_id)

          case Repo.update(User.password_changeset(user, %{password: new_password})) do
            {:ok, updated} ->
              Repo.update_all(
                from(t in UserToken, where: t.id == ^user_token.id),
                set: [used_at: now]
              )

              revoke_all_sessions(updated.id)
              updated

            {:error, %Ecto.Changeset{} = cs} ->
              Repo.rollback(cs)
          end
        end)
        |> case do
          {:ok, %User{} = updated} -> {:ok, updated}
          {:error, %Ecto.Changeset{} = cs} -> {:error, Error.bad_request(changeset_error_message(cs))}
          {:error, reason} -> {:error, Error.internal_error("Password reset failed: #{inspect(reason)}")}
        end
        end
    end
  end

  @spec public_profile(User.t()) :: map()
  def public_profile(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      username: user.username,
      verified: user.verified,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  defp create_refresh_token(%User{} = user, meta) do
    ip = Map.get(meta, :ip) || Map.get(meta, "ip")
    user_agent = Map.get(meta, :user_agent) || Map.get(meta, "user_agent")

    refresh_token = Auth.generate_refresh_token()
    token_hash = Auth.token_hash(refresh_token)
    expires_at = DateTime.add(DateTime.utc_now(), Auth.refresh_token_ttl_secs(), :second)

    %RefreshToken{}
    |> RefreshToken.changeset(%{
      user_id: user.id,
      token_hash: token_hash,
      expires_at: expires_at,
      ip: ip,
      user_agent: user_agent
    })
    |> Repo.insert()
    |> case do
      {:ok, _row} -> {:ok, refresh_token}
      {:error, %Ecto.Changeset{} = cs} -> {:error, Error.internal_error("Failed to create refresh token: #{inspect(cs.errors)}")}
      {:error, reason} -> {:error, Error.internal_error("Failed to create refresh token: #{inspect(reason)}")}
    end
  end

  defp rotate_refresh_token(%RefreshToken{} = current, meta) do
    now = DateTime.utc_now()
    new_refresh = Auth.generate_refresh_token()
    new_hash = Auth.token_hash(new_refresh)
    expires_at = DateTime.add(now, Auth.refresh_token_ttl_secs(), :second)

    ip = Map.get(meta, :ip) || Map.get(meta, "ip")
    user_agent = Map.get(meta, :user_agent) || Map.get(meta, "user_agent")

    multi =
      Multi.new()
      |> Multi.update_all(
        :revoke_current,
        from(t in RefreshToken, where: t.id == ^current.id and is_nil(t.revoked_at)),
        set: [revoked_at: now, replaced_by_token_hash: new_hash]
      )
      |> Multi.run(:ensure_active, fn _repo, %{revoke_current: {count, _}} ->
        if count == 1 do
          {:ok, :ok}
        else
          {:error, :token_used}
        end
      end)
      |> Multi.insert(:insert_new, RefreshToken.changeset(%RefreshToken{}, %{
        user_id: current.user_id,
        token_hash: new_hash,
        expires_at: expires_at,
        ip: ip,
        user_agent: user_agent
      }))

    Repo.transaction(multi)
    |> case do
      {:ok, _result} ->
        with {:ok, user} <- get_user(current.user_id),
             {:ok, access_token} <- Auth.issue_access_token(user.id) do
          {:ok, %{access_token: access_token, refresh_token: new_refresh, user: user}}
        end

      {:error, :ensure_active, :token_used, _changes} ->
        {:error, Error.unauthorized("Refresh token has been rotated")}

      {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
        {:error, Error.internal_error("Refresh failed: #{changeset_error_message(cs)}")}

      {:error, _step, reason, _changes} ->
        {:error, Error.internal_error("Refresh failed: #{inspect(reason)}")}
    end
  end

  defp normalize_changeset_error({:ok, result}, _default_message), do: {:ok, result}

  defp normalize_changeset_error({:error, %Ecto.Changeset{} = cs}, default_message) do
    {:error, Error.bad_request("#{default_message}: #{changeset_error_message(cs)}")}
  end

  defp normalize_changeset_error({:error, reason}, default_message) do
    {:error, Error.internal_error("#{default_message}: #{inspect(reason)}")}
  end

  defp changeset_error_message(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field} #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
