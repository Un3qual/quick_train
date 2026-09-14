defmodule QuickTrain.Datasets.ReadAuthority do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment
  import Ash.Expr
  def describe(_), do: "current ordinary dataset authority for the source row"

  def filter(%{id: id}, %{resource: resource}, _opts) do
    authority = authority(id)

    case resource do
      QuickTrain.Datasets.DatasetValue ->
        expr(exists(RoleAssignment, organization_id == parent(organization_id) and ^authority))

      QuickTrain.Datasets.DatasetFieldDefinition ->
        expr(
          exists(
            RoleAssignment,
            organization_id == parent(record_type.schema_version.dataset.organization_id) and
              ^authority
          )
        )

      QuickTrain.Datasets.DatasetRecordType ->
        expr(
          exists(
            RoleAssignment,
            organization_id == parent(schema_version.dataset.organization_id) and ^authority
          )
        )

      _ ->
        expr(
          exists(
            RoleAssignment,
            organization_id == parent(dataset_value.organization_id) and ^authority
          )
        )
    end
  end

  def filter(_, _, _), do: false

  defp authority(id),
    do:
      expr(
        user_id == ^id and user.status == "active" and organization.status == "active" and
          exists(role.role_capabilities, capability.key in ["datasets.read", "datasets.manage"]) and
          exists(organization.memberships, user_id == ^id and status == "active")
      )
end
