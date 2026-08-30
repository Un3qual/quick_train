defmodule QuickTrain.Authentication.Api.Actions.ExchangeOidcLogin do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  import Bitwise, only: [bor: 2, bxor: 2]

  require Ash.Query

  alias QuickTrain.Accounts.{
    ExternalIdentity,
    Oidc,
    OidcLoginTransaction,
    Session,
    User
  }

  alias QuickTrain.Authentication.{Error, OidcExchangeResult}
  alias QuickTrain.AshError

  @finalization_attempts 2

  @impl true
  def run(input, _opts, _context) do
    Error.wrap(:exchange, exchange_login(input))
  end

  defp exchange_login(input) do
    resource = OidcLoginTransaction
    code = input.arguments.code
    state = input.arguments.state
    client_proof = input.arguments.client_proof

    with :ok <- validate_exchange_input(code, state, client_proof),
         {:ok, transaction} <- load_transaction(resource, state),
         :ok <- verify_client_proof(transaction, client_proof),
         {:ok, claimed_transaction} <- claim_transaction(transaction),
         {:ok, claims} <- exchange_with_provider(claimed_transaction, code),
         {:ok, identity_claims} <- validate_identity_claims(claims),
         {:ok, result} <- finalize_exchange(resource, claimed_transaction, identity_claims) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_exchange_input(code, state, client_proof)
       when is_binary(code) and code != "" and is_binary(state) and state != "" and
              is_binary(client_proof) and client_proof != "",
       do: :ok

  defp validate_exchange_input(_code, _state, _client_proof),
    do: {:error, :invalid_oidc_exchange}

  defp load_transaction(resource, state) do
    state_hash = sha256(state)

    case resource
         |> Ash.Query.filter(state_hash == ^state_hash)
         |> Ash.read_one(authorize?: false) do
      {:ok, transaction} when not is_nil(transaction) -> {:ok, transaction}
      {:ok, nil} -> {:error, :invalid_oidc_exchange}
      {:error, _error} -> {:error, :invalid_oidc_exchange}
    end
  end

  defp verify_client_proof(transaction, client_proof) do
    presented_hash = sha256(client_proof)
    expected_hash = transaction.redemption_secret_hash

    if constant_time_equal?(expected_hash, presented_hash) do
      :ok
    else
      {:error, :invalid_oidc_exchange}
    end
  end

  defp claim_transaction(transaction) do
    result =
      transaction
      |> Ash.Changeset.for_update(:claim, %{})
      |> Ash.update(authorize?: false)

    case result do
      {:ok, claimed_transaction} -> {:ok, claimed_transaction}
      {:error, _error} -> {:error, :invalid_oidc_exchange}
    end
  end

  defp exchange_with_provider(transaction, code) do
    nonce = Oidc.nonce_for_verifier(transaction.code_verifier)

    if secure_compare_hash(transaction.nonce_hash, nonce) do
      options = %{
        redirect_uri: transaction.callback_uri,
        pkce_verifier: transaction.code_verifier,
        require_pkce: true,
        nonce: nonce
      }

      case Oidc.exchange_code(code, options) do
        {:ok, claims} when is_map(claims) -> {:ok, claims}
        {:error, _error} -> {:error, :provider_exchange_failed}
      end
    else
      {:error, :invalid_oidc_exchange}
    end
  end

  defp validate_identity_claims(claims) do
    issuer = claims["iss"]
    subject = claims["sub"]

    if valid_identity_claim?(issuer) and valid_identity_claim?(subject) and
         issuer == Oidc.issuer() do
      {:ok,
       %{
         issuer: issuer,
         subject: subject,
         email: claims["email"],
         email_verified: claims["email_verified"] === true,
         display_name: display_name(claims),
         claims: claims
       }}
    else
      {:error, :invalid_provider_identity}
    end
  end

  defp valid_identity_claim?(value), do: is_binary(value) and String.trim(value) != ""

  defp display_name(claims) do
    [claims["name"], claims["preferred_username"]]
    |> Enum.find_value(&trimmed_nonblank/1)
  end

  defp trimmed_nonblank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed_nonblank(_value), do: nil

  defp finalize_exchange(
         transaction_resource,
         transaction,
         identity_claims,
         attempts \\ @finalization_attempts
       ) do
    resources = [transaction_resource, ExternalIdentity, User, Session]

    case Ash.transact(resources, fn ->
           transaction_result(
             finalize_in_transaction(transaction_resource, transaction, identity_claims)
           )
         end) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} when attempts > 1 ->
        if uniqueness_conflict?(error) do
          finalize_exchange(
            transaction_resource,
            transaction,
            identity_claims,
            attempts - 1
          )
        else
          {:error, finalization_error(error)}
        end

      {:error, error} ->
        {:error, finalization_error(error)}
    end
  end

  defp transaction_result({:error, reason}) when is_atom(reason) do
    {:error, Error.exception(operation: :exchange, category: reason)}
  end

  defp transaction_result(result), do: result

  defp finalize_in_transaction(transaction_resource, transaction, identity_claims) do
    with {:ok, locked_transaction} <-
           lock_claimed_transaction(transaction_resource, transaction.id),
         {:ok, user} <- resolve_user(identity_claims),
         {:ok, issued} <- issue_bearer_session(user.id),
         {:ok, _consumed_transaction} <- consume_transaction(locked_transaction) do
      %OidcExchangeResult{
        token: issued.token,
        session_id: issued.session_id,
        expires_at: issued.expires_at,
        user: user
      }
    end
  end

  defp lock_claimed_transaction(resource, transaction_id) do
    transaction =
      resource
      |> Ash.Query.filter(id == ^transaction_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case transaction do
      %{status: "exchanging"} -> {:ok, transaction}
      _transaction -> {:error, :invalid_oidc_exchange}
    end
  end

  defp resolve_user(identity_claims) do
    case lock_identity(identity_claims.issuer, identity_claims.subject) do
      {:ok, nil} -> create_identity_graph(identity_claims)
      {:ok, identity} -> resolve_existing_identity(identity, identity_claims.claims)
      {:error, error} -> {:error, error}
    end
  end

  defp lock_identity(issuer, subject) do
    ExternalIdentity
    |> Ash.Query.filter(issuer == ^issuer and subject == ^subject)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp resolve_existing_identity(%{status: "active"} = identity, claims) do
    with {:ok, %{status: "active"} = user} <- lock_user(identity.user_id),
         {:ok, _identity} <- refresh_identity(identity, claims) do
      {:ok, user}
    else
      {:ok, %{}} -> {:error, :inactive_account}
      {:ok, nil} -> {:error, :identity_conflict}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_existing_identity(%{}, _claims),
    do: {:error, :inactive_account}

  defp lock_user(user_id) do
    User
    |> Ash.Query.filter(id == ^user_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp create_identity_graph(identity_claims) do
    with {:ok, email} <- verified_email(identity_claims),
         {:ok, user} <-
           create(User, :create_from_oidc, %{
             email: email,
             display_name: identity_claims.display_name || email_local_part(email)
           }),
         {:ok, _identity} <-
           create(ExternalIdentity, :create_identity, %{
             user_id: user.id,
             issuer: identity_claims.issuer,
             subject: identity_claims.subject,
             claims: identity_claims.claims
           }) do
      {:ok, user}
    end
  end

  defp refresh_identity(identity, claims) do
    identity
    |> Ash.Changeset.for_update(:refresh, %{claims: claims})
    |> Ash.update(authorize?: false)
  end

  defp issue_bearer_session(user_id) do
    Session
    |> Ash.ActionInput.for_action(:issue_bearer, %{user_id: user_id})
    |> Ash.run_action(authorize?: false)
  end

  defp consume_transaction(transaction) do
    transaction
    |> Ash.Changeset.for_update(:consume, %{})
    |> Ash.update(authorize?: false)
  end

  defp create(resource, action, attributes) do
    resource
    |> Ash.Changeset.for_create(action, attributes)
    |> Ash.create(authorize?: false)
  end

  defp verified_email(%{email_verified: true, email: email}) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    case String.split(email, "@", parts: 2) do
      [local_part, domain] when local_part != "" and domain != "" -> {:ok, email}
      _invalid -> {:error, :verified_email_required}
    end
  end

  defp verified_email(_identity_claims), do: {:error, :verified_email_required}

  defp email_local_part(email), do: email |> String.split("@", parts: 2) |> hd()

  defp uniqueness_conflict?(error) do
    AshError.constraint?(error, [
      "users_email_index",
      "external_identities_issuer_subject_index",
      "external_identities_user_issuer_index",
      "sessions_token_hash_index"
    ])
  end

  defp finalization_error(error) do
    cond do
      uniqueness_conflict?(error) -> :account_linking_conflict
      AshError.reason?(error, :inactive_account) -> :inactive_account
      AshError.reason?(error, :verified_email_required) -> :verified_email_required
      AshError.reason?(error, :invalid_oidc_exchange) -> :invalid_oidc_exchange
      true -> :account_linking_conflict
    end
  end

  defp secure_compare_hash(expected_hash, raw_value) when is_binary(expected_hash) do
    actual_hash = sha256(raw_value)

    constant_time_equal?(expected_hash, actual_hash)
  end

  defp secure_compare_hash(_expected_hash, _raw_value), do: false

  defp constant_time_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    constant_time_difference(left, right, 0) == 0
  end

  defp constant_time_equal?(_left, _right), do: false

  defp constant_time_difference(<<>>, <<>>, difference), do: difference

  defp constant_time_difference(
         <<left, left_rest::binary>>,
         <<right, right_rest::binary>>,
         difference
       ) do
    constant_time_difference(left_rest, right_rest, bor(difference, bxor(left, right)))
  end

  defp sha256(value), do: :crypto.hash(:sha256, value)
end
