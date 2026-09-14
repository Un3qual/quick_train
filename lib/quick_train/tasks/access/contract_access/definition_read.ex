defmodule QuickTrain.Tasks.Access.ContractAccess.DefinitionRead do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.Attempt
  require Ash.Query

  @impl true
  def prepare(query, _opts, context),
    do: Ash.Query.before_action(query, &scope_query(&1, context.actor))

  defp scope_query(query, actor) do
    if is_nil(actor), do: Error.reject!(:forbidden)
    args = query.arguments
    project = Access.project!(args.organization_id, args.project_id)

    if args[:attempt_id] do
      attempt =
        Attempt
        |> Ash.Query.filter(id == ^args.attempt_id and project_id == ^project.id)
        |> Ash.read_one!(authorize?: false)
        |> Access.found!()

      Access.owner!(project, attempt, actor)
    else
      Access.manager!(project, actor, "tasks.results.read")
    end

    case query.resource.source_resource() do
      QuickTrain.Forms.FormVersion ->
        Ash.Query.filter(query, id == ^project.form_version_id)

      QuickTrain.Datasets.DatasetFieldDefinition ->
        Ash.Query.filter(
          query,
          record_type_id == ^project.root_record_type_id and
            exists(
              QuickTrain.Projects.ProjectInputBinding,
              field_definition_id == parent(id) and project_id == ^project.id
            )
        )

      _ ->
        Ash.Query.filter(query, version_id == ^project.form_version_id)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Query.add_error(query, error)
  end
end
