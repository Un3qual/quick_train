defmodule QuickTrain.EnterpriseIdentity.DirectoryUser.Changes.DeactivateMembership do
  @moduledoc false

  use Ash.Resource.Change

  alias QuickTrain.Organizations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, directory_user ->
      with {:ok, membership} <-
             Organizations.get_membership(directory_user.membership_id, authorize?: false),
           {:ok, _membership} <-
             Organizations.deactivate_membership(membership, authorize?: false) do
        {:ok, directory_user}
      end
    end)
  end

  @impl true
  def atomic(changeset, opts, context) do
    {:ok, change(changeset, opts, context)}
  end
end
