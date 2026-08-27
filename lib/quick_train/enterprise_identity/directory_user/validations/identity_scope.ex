defmodule QuickTrain.EnterpriseIdentity.DirectoryUser.Validations.IdentityScope do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.EnterpriseIdentity
  alias QuickTrain.EnterpriseIdentity.EnterpriseConnection
  alias QuickTrain.Organizations
  alias QuickTrain.Organizations.Membership

  @impl true
  def validate(changeset, _opts, _context) do
    enterprise_connection_id =
      Ash.Changeset.get_attribute(changeset, :enterprise_connection_id)

    membership_id = Ash.Changeset.get_attribute(changeset, :membership_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    with {:ok, %EnterpriseConnection{organization_id: organization_id}} <-
           EnterpriseIdentity.get_enterprise_connection(enterprise_connection_id,
             authorize?: false
           ),
         {:ok,
          %Membership{
            organization_id: ^organization_id,
            user_id: ^user_id,
            status: "active"
          }} <- Organizations.get_membership(membership_id, authorize?: false) do
      :ok
    else
      _mismatched_scope ->
        {:error, field: :membership_id, message: "identity scope mismatch"}
    end
  end
end
