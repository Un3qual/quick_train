defmodule QuickTrain.Accounts do
  @moduledoc "Global user accounts, external identities, and account-required sessions."

  alias QuickTrain.Accounts.{Session, User}
  alias QuickTrain.Organizations

  def register_user(email, display_name) when is_binary(email) and is_binary(display_name) do
    User
    |> Ash.Changeset.for_create(:register, %{
      email: email |> String.trim() |> String.downcase(),
      display_name: String.trim(display_name)
    })
    |> Ash.create(authorize?: false)
  end

  def get_user(user_id) do
    case Ash.get(User, user_id, authorize?: false) do
      {:ok, nil} -> {:error, :not_found}
      other -> other
    end
  end

  def issue_session(user_id, attrs) when is_map(attrs) do
    with {:ok, %User{status: "active"}} <- active_user(user_id),
         :ok <- validate_scope(user_id, Map.get(attrs, :organization_id)) do
      now = DateTime.utc_now()

      Session
      |> Ash.Changeset.for_create(:issue, %{
        user_id: user_id,
        organization_id: Map.get(attrs, :organization_id),
        authentication_method: Map.get(attrs, :authentication_method, "oidc"),
        token_hash: Map.get(attrs, :token_hash),
        issued_at: now,
        expires_at: Map.get(attrs, :expires_at, DateTime.add(now, 8, :hour))
      })
      |> Ash.create(authorize?: false)
    end
  end

  defp active_user(user_id) do
    case get_user(user_id) do
      {:ok, %User{status: "active"} = user} -> {:ok, user}
      _other -> {:error, :account_required}
    end
  end

  defp validate_scope(_user_id, nil), do: :ok

  defp validate_scope(user_id, organization_id) do
    if Organizations.member?(organization_id, user_id),
      do: :ok,
      else: {:error, :membership_required}
  end
end
