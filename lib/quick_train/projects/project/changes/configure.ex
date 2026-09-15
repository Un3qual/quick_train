defmodule QuickTrain.Projects.Project.Changes.Configure do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Datasets.DatasetSchemaVersion
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Projects.{Error, Management}
  require Ash.Query

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &configure(&1, context.actor))

  defp configure(changeset, actor) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    Management.authorize!(actor, organization_id)

    if changeset.action.type == :create do
      changeset |> schema!(organization_id, actor) |> form!(organization_id, actor)
    else
      if changeset.data.state != :draft, do: Error.reject!(:project_not_draft)
      # Reapply explicit values to the locked record even when equal to the caller's stale copy.
      Ash.Changeset.force_change_attributes(changeset, changeset.casted_attributes)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end

  defp schema!(changeset, organization_id, actor) do
    Management.authorize!(actor, organization_id, "datasets.read")
    dataset_id = Ash.Changeset.get_attribute(changeset, :dataset_id)
    schema_id = Ash.Changeset.get_attribute(changeset, :schema_version_id)

    schema =
      DatasetSchemaVersion
      |> Ash.Query.filter(
        id == ^schema_id and dataset_id == ^dataset_id and
          dataset.organization_id == ^organization_id and state == :published
      )
      |> Ash.read_one!(authorize?: false)

    if is_nil(schema), do: Error.reject!(:invalid_project_configuration)

    Ash.Changeset.force_change_attribute(
      changeset,
      :root_record_type_id,
      schema.root_record_type_id
    )
  end

  defp form!(changeset, organization_id, actor) do
    version_id = Ash.Changeset.get_attribute(changeset, :form_version_id)
    Management.authorize!(actor, organization_id, "forms.read")

    version =
      FormVersion
      |> Ash.Query.filter(
        id == ^version_id and form.organization_id == ^organization_id and state == :published
      )
      |> Ash.read_one!(authorize?: false)

    if is_nil(version), do: Error.reject!(:invalid_project_configuration)
    Ash.Changeset.force_change_attribute(changeset, :form_id, version.form_id)
  end
end
