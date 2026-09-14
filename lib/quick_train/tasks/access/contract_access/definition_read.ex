defmodule QuickTrain.Tasks.Access.ContractAccess.DefinitionRead do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.Attempt
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
