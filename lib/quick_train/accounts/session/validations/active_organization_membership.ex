defmodule QuickTrain.Accounts.Session.Validations.ActiveOrganizationMembership do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.Organizations

  @impl true
  def validate(changeset, _opts, _context) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    if is_nil(organization_id) or Organizations.member?(organization_id, user_id) do
      :ok
    else
      {:error, field: :organization_id, message: "active membership required"}
    end
  end
end
