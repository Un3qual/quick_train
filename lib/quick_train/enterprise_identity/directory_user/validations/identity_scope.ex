defmodule QuickTrain.EnterpriseIdentity.DirectoryUser.Validations.IdentityScope do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.EnterpriseIdentity.EnterpriseConnection
  alias QuickTrain.Organizations.Membership

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    with {:ok, scopes} <- load_scopes([changeset]),
         true <- valid_scope?(changeset, scopes) do
      :ok
    else
      _mismatched_scope ->
        {:error, scope_error()}
    end
  end

  @impl true
  def batch_validate(changesets, _opts, _context) do
    case load_scopes(changesets) do
      {:ok, scopes} ->
        Enum.map(changesets, &validate_changeset(&1, scopes))

      {:error, error} ->
        Enum.map(changesets, &Ash.Changeset.add_error(&1, error))
    end
  end

  defp load_scopes(changesets) do
    connection_ids = attribute_values(changesets, :enterprise_connection_id)
    membership_ids = attribute_values(changesets, :membership_id)

    with {:ok, connections} <- read_by_ids(EnterpriseConnection, connection_ids),
         {:ok, memberships} <- read_by_ids(Membership, membership_ids) do
      {:ok,
       %{
         connections: Map.new(connections, &{&1.id, &1.organization_id}),
         memberships: Map.new(memberships, &{&1.id, &1})
       }}
    end
  end

  defp read_by_ids(resource, ids) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read(authorize?: false)
  end

  defp attribute_values(changesets, attribute) do
    changesets
    |> Enum.map(&Ash.Changeset.get_attribute(&1, attribute))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp validate_changeset(changeset, scopes) do
    if valid_scope?(changeset, scopes) do
      changeset
    else
      Ash.Changeset.add_error(changeset, scope_error())
    end
  end

  defp valid_scope?(changeset, scopes) do
    connection_id = Ash.Changeset.get_attribute(changeset, :enterprise_connection_id)
    membership_id = Ash.Changeset.get_attribute(changeset, :membership_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    with organization_id when not is_nil(organization_id) <-
           Map.get(scopes.connections, connection_id),
         %Membership{
           organization_id: ^organization_id,
           user_id: ^user_id,
           status: "active"
         } <- Map.get(scopes.memberships, membership_id) do
      true
    else
      _mismatched_scope -> false
    end
  end

  defp scope_error do
    [field: :membership_id, message: "identity scope mismatch"]
  end
end
