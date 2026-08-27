defmodule QuickTrain.Accounts do
  @moduledoc "Global user accounts, external identities, and account-required sessions."

  # alias QuickTrain.Accounts.{Session, User}
  # alias QuickTrain.Organizations

  # def issue_session(user_id, attrs) when is_map(attrs) do
  #   with {:ok, %User{status: "active"}} <- active_user(user_id),
  #        :ok <- validate_scope(user_id, Map.get(attrs, :organization_id)) do
  #     now = DateTime.utc_now()

  #     Session
  #     |> Ash.Changeset.for_create(:issue, %{
  #       user_id: user_id,
  #       organization_id: Map.get(attrs, :organization_id),
  #       authentication_method: Map.get(attrs, :authentication_method, "oidc"),
  #       token_hash: Map.get(attrs, :token_hash),
  #       issued_at: now,
  #       expires_at: Map.get(attrs, :expires_at, DateTime.add(now, 8, :hour))
  #     })
  #     |> Ash.create(authorize?: false)
  #   end
  # end

  # defp validate_scope(_user_id, nil), do: :ok

  # defp validate_scope(user_id, organization_id) do
  #   if Organizations.member?(organization_id, user_id),
  #     do: :ok,
  #     else: {:error, :membership_required}
  # end
end
