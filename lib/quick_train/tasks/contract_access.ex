defmodule QuickTrain.Tasks.ContractAccess do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Datasets.{DatasetFieldDefinition, DatasetValue}
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Tasks.{Attempt, ReadAccess, Task, TaskInput}
  import Ash.Expr

  def describe(_),
    do: "an exact published definition or bound value of currently authorized issued work"

  def filter(%{id: _} = actor, %{resource: resource, query: query}, _opts) do
    if query.action.name == :get_task_definition or is_map(query.context[:accessing_from]),
      do: definition_filter(resource, actor),
      else: false
  end

  def filter(_, _, _), do: false

  defp definition_filter(FormVersion, actor) do
    live = ReadAccess.live_attempt(actor)
    results = ReadAccess.result_authority(actor)

    expr(
      exists(Attempt, form_version_id == parent(id) and ^live) or
        exists(Task, form_version_id == parent(id) and ^results)
    )
  end

  defp definition_filter(DatasetValue, actor), do: value_access(actor)

  defp definition_filter(resource, actor)
       when resource in [
              DatasetValue.Text,
              DatasetValue.Integer,
              DatasetValue.Decimal,
              DatasetValue.Boolean,
              DatasetValue.DateTime,
              DatasetValue.Asset
            ] do
    values = value_access(actor)
    expr(exists(DatasetValue, id == parent(dataset_value_id) and ^values))
  end

  defp definition_filter(DatasetFieldDefinition, actor) do
    input_access = ReadAccess.authorized_filter(TaskInput, actor)

    expr(
      exists(
        TaskInput,
        ^input_access and
          exists(
            project.bindings,
            field_definition_id == parent(parent(id)) and
              requirement.input_slot_id == parent(input_slot_id)
          )
      )
    )
  end

  defp definition_filter(_resource, actor) do
    live = ReadAccess.live_attempt(actor)
    results = ReadAccess.result_authority(actor)

    expr(
      exists(Attempt, form_version_id == parent(version_id) and ^live) or
        exists(Task, form_version_id == parent(version_id) and ^results)
    )
  end

  defp value_access(actor) do
    input_access = ReadAccess.authorized_filter(TaskInput, actor)

    expr(
      exists(
        TaskInput,
        revision.root_record_id == parent(record_id) and ^input_access and
          exists(
            project.bindings,
            field_definition_id == parent(parent(field_definition_id)) and
              requirement.input_slot_id == parent(input_slot_id)
          )
      )
    )
  end
end

defmodule QuickTrain.Tasks.ContractAccess.DefinitionRead do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.{Access, Attempt, Error}
  require Ash.Query

  def prepare(query, _opts, context) do
    if is_nil(context.actor), do: Error.reject!(:forbidden)
    args = query.arguments

    {:ok, project} =
      QuickTrain.Repo.transaction(fn ->
        project = Access.project!(args.organization_id, args.project_id)

        if args[:attempt_id] do
          attempt =
            Attempt
            |> Ash.Query.filter(id == ^args.attempt_id and project_id == ^project.id)
            |> Ash.read_one!(authorize?: false)
            |> Access.found!()

          Access.owner!(project, attempt, context.actor)
        else
          Access.manager!(project, context.actor, "tasks.results.read")
        end

        project
      end)

    case query.resource do
      QuickTrain.Forms.FormVersion ->
        Ash.Query.filter(query, id == ^project.form_version_id)

      QuickTrain.Datasets.DatasetFieldDefinition ->
        Ash.Query.filter(
          query,
          record_type_id == ^project.root_record_type_id and
            exists(project_bindings, project_id == ^project.id)
        )

      _ ->
        Ash.Query.filter(query, version_id == ^project.form_version_id)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Query.add_error(query, error)
  end
end

defmodule QuickTrain.Tasks.ContractAccess.DatasetSchemaRead do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment
  import Ash.Expr
  def describe(_), do: "ordinary dataset inspection is authorized before reverse schema traversal"

  def filter(%{id: id}, _, _) do
    expr(
      exists(
        RoleAssignment,
        organization_id == parent(schema_version.dataset.organization_id) and user_id == ^id and
          user.status == "active" and organization.status == "active" and
          exists(role.role_capabilities, capability.key in ["datasets.read", "datasets.manage"]) and
          exists(organization.memberships, user_id == ^id and status == "active")
      )
    )
  end

  def filter(_, _, _), do: false
end

defmodule QuickTrain.Tasks.ContractAccess.DatasetAuthority do
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
