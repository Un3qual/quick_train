defmodule QuickTrain.Authorization.Checks.SourceRead do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment
  import Ash.Expr
  def describe(_), do: "current ordinary capability for the source row"

  def filter(%{id: id}, %{resource: resource}, _opts) do
    authority = authority(id, resource)

    case resource do
      resource when resource in [QuickTrain.Datasets.DatasetValue, QuickTrain.Assets.Asset] ->
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

  defp authority(id, resource) do
    capabilities =
      if resource == QuickTrain.Assets.Asset,
        do: ["assets.read", "datasets.read", "datasets.manage"],
        else: ["datasets.read", "datasets.manage"]

    expr(
      user_id == ^id and user.status == "active" and organization.status == "active" and
        exists(role.role_capabilities, capability.key in ^capabilities) and
        exists(organization.memberships, user_id == ^id and status == "active")
    )
  end
end
