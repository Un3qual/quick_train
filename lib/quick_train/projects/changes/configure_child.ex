defmodule QuickTrain.Projects.Changes.ConfigureChild do
  @moduledoc false
  use Ash.Resource.Change

  alias QuickTrain.Projects.{
    Error,
    Management,
    ProjectActivation,
    ProjectInputBinding,
    ProjectSlotPolicy,
    ProjectWorkerAccess
  }

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &configure(&1, context.actor))

  defp configure(changeset, actor) do
    project =
      Management.lock!(
        Ash.Changeset.get_argument(changeset, :organization_id),
        Ash.Changeset.get_attribute(changeset, :project_id)
      )

    Management.authorize!(actor, project.organization_id)

    if changeset.resource != ProjectWorkerAccess and project.state != :draft,
      do: Error.reject!(:project_not_draft)

    if changeset.action.type == :destroy do
      Ash.Changeset.filter(changeset, project_id: project.id)
    else
      configure(changeset, project, actor)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end

  defp configure(%{resource: ProjectInputBinding} = changeset, project, actor) do
    Management.authorize!(actor, project.organization_id, "datasets.read")
    Management.authorize!(actor, project.organization_id, "forms.read")

    ProjectActivation.validate_binding!(
      project,
      Ash.Changeset.get_attribute(changeset, :requirement_id),
      Ash.Changeset.get_attribute(changeset, :field_definition_id)
    )

    Ash.Changeset.force_change_attributes(
      changeset,
      Map.take(project, [:schema_version_id, :root_record_type_id, :form_version_id])
    )
  end

  defp configure(%{resource: ProjectSlotPolicy} = changeset, project, actor) do
    Management.authorize!(actor, project.organization_id, "forms.read")

    ProjectActivation.validate_slot!(
      project,
      Ash.Changeset.get_attribute(changeset, :input_slot_id),
      Ash.Changeset.get_attribute(changeset, :item_count)
    )

    Ash.Changeset.force_change_attribute(changeset, :form_version_id, project.form_version_id)
  end

  defp configure(%{resource: ProjectWorkerAccess} = changeset, _project, _actor), do: changeset
end
