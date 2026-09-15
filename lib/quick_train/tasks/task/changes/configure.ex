defmodule QuickTrain.Tasks.Task.Changes.Configure do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Projects.{Error, Management, ProjectActivation}
  alias QuickTrain.Tasks.Task.Identity
  alias QuickTrain.Tasks.TaskInput

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &configure(&1, context.actor))

  defp configure(changeset, actor) do
    organization_id = Ash.Changeset.get_argument_or_attribute(changeset, :organization_id)

    project =
      Management.lock!(organization_id, Ash.Changeset.get_attribute(changeset, :project_id))

    Management.authorize!(actor, project.organization_id)
    if project.state != :draft, do: Error.reject!(:project_not_draft)

    if changeset.action.type == :destroy do
      Ash.Changeset.filter(changeset,
        project_id: project.id,
        organization_id: project.organization_id
      )
    else
      Management.authorize!(actor, project.organization_id, "datasets.read")
      Management.authorize!(actor, project.organization_id, "forms.read")

      inputs =
        ProjectActivation.task_inputs!(project, Ash.Changeset.get_argument(changeset, :inputs))

      scope =
        Map.take(project, [:organization_id, :form_version_id, :dataset_id, :schema_version_id])
        |> Map.put(:project_id, project.id)

      changeset
      |> Ash.Changeset.force_change_attributes(%{
        form_version_id: project.form_version_id,
        canonical_key: Identity.key(inputs)
      })
      |> Ash.Changeset.after_action(fn _changeset, task ->
        inputs
        |> Enum.map(&Map.merge(&1, Map.put(scope, :task_id, task.id)))
        |> Ash.bulk_create!(TaskInput, :create_internal,
          authorize?: false,
          transaction: :all,
          stop_on_error?: true
        )

        {:ok, task}
      end)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end
end
