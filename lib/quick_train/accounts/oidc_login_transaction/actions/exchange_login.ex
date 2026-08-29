defmodule QuickTrain.Accounts.OidcLoginTransaction.Actions.ExchangeLogin do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Accounts

  alias QuickTrain.Accounts.{
    ExternalIdentity,
    Oidc,
    OidcLoginTransaction,
    Session,
    User
  }

  @finalization_attempts 2

  @impl true
  def run(input, _opts, _context) do
    code = input.arguments.code
    state = input.arguments.state
    client_proof = input.arguments.client_proof

    with :ok <- validate_exchange_input(code, state, client_proof),
         {:ok, transaction} <- load_transaction(state),
         :ok <- verify_client_proof(transaction, client_proof),
         {:ok, claimed_transaction} <- claim_transaction(transaction),
         {:ok, claims} <- exchange_with_provider(claimed_transaction, code),
         {:ok, identity_claims} <- validate_identity_claims(claims),
         {:ok, result} <- finalize_exchange(claimed_transaction, identity_claims) do
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

  defp load_transaction(state) do
    state_hash = sha256(state)

    case Accounts.get_oidc_login(state_hash,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %OidcLoginTransaction{} = transaction} -> {:ok, transaction}
      {:ok, nil} -> {:error, :invalid_oidc_exchange}
      {:error, _error} -> {:error, :invalid_oidc_exchange}
    end
  end

  defp verify_client_proof(transaction, client_proof) do
    presented_hash = sha256(client_proof)
    expected_hash = transaction.redemption_secret_hash

    if is_binary(expected_hash) and byte_size(expected_hash) == byte_size(presented_hash) and
         Plug.Crypto.secure_compare(expected_hash, presented_hash) do
      :ok
    else
      {:error, :invalid_oidc_exchange}
    end
  end

  defp claim_transaction(transaction) do
    case Accounts.claim_oidc_login(transaction, authorize?: false) do
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

  defp finalize_exchange(transaction, identity_claims, attempts \\ @finalization_attempts) do
    resources = [OidcLoginTransaction, ExternalIdentity, User, Session]

    case Ash.transact(resources, fn -> finalize_in_transaction(transaction, identity_claims) end) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} when attempts > 1 ->
        if uniqueness_conflict?(error) do
          finalize_exchange(transaction, identity_claims, attempts - 1)
        else
          {:error, finalization_error(error)}
        end

      {:error, error} ->
        {:error, finalization_error(error)}
    end
  end

  defp finalize_in_transaction(transaction, identity_claims) do
    with {:ok, locked_transaction} <- lock_claimed_transaction(transaction.id),
         {:ok, user} <- resolve_user(identity_claims),
         {:ok, issued} <- Accounts.issue_bearer_session(user.id, authorize?: false),
         {:ok, _consumed_transaction} <-
           Accounts.consume_oidc_login(locked_transaction, authorize?: false) do
      %{
        token: issued.token,
        session_id: issued.session_id,
        expires_at: issued.expires_at,
        user: user
      }
    end
  end

  defp lock_claimed_transaction(transaction_id) do
    transaction =
      OidcLoginTransaction
      |> Ash.Query.filter(id == ^transaction_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case transaction do
      %OidcLoginTransaction{status: "exchanging"} -> {:ok, transaction}
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

  defp resolve_existing_identity(%ExternalIdentity{status: "active"} = identity, claims) do
    with {:ok, %User{status: "active"} = user} <- lock_user(identity.user_id),
         {:ok, _identity} <-
           Accounts.refresh_external_identity(identity, %{claims: claims}, authorize?: false) do
      {:ok, user}
    else
      {:ok, %User{}} -> {:error, :inactive_account}
      {:ok, nil} -> {:error, :identity_conflict}
      {:error, error} -> {:error, error}
    end
  end

  defp resolve_existing_identity(%ExternalIdentity{}, _claims),
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
           Accounts.create_oidc_user(
             %{
               email: email,
               display_name: identity_claims.display_name || email_local_part(email)
             },
             authorize?: false
           ),
         {:ok, _identity} <-
           Accounts.create_external_identity(
             %{
               user_id: user.id,
               issuer: identity_claims.issuer,
               subject: identity_claims.subject,
               claims: identity_claims.claims
             },
             authorize?: false
           ) do
      {:ok, user}
    end
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
    message = Exception.message(error)

    Enum.any?(
      [
        "users_email_index",
        "external_identities_issuer_subject_index",
        "external_identities_user_issuer_index",
        "sessions_token_hash_index"
      ],
      &String.contains?(message, &1)
    )
  end

  defp finalization_error(error) do
    message = Exception.message(error)

    cond do
      uniqueness_conflict?(error) -> :account_linking_conflict
      String.contains?(message, "inactive_account") -> :inactive_account
      String.contains?(message, "verified_email_required") -> :verified_email_required
      String.contains?(message, "invalid_oidc_exchange") -> :invalid_oidc_exchange
      true -> :account_linking_conflict
    end
  end

  defp secure_compare_hash(expected_hash, raw_value) when is_binary(expected_hash) do
    actual_hash = sha256(raw_value)

    byte_size(expected_hash) == byte_size(actual_hash) and
      Plug.Crypto.secure_compare(expected_hash, actual_hash)
  end

  defp secure_compare_hash(_expected_hash, _raw_value), do: false
  defp sha256(value), do: :crypto.hash(:sha256, value)
end
