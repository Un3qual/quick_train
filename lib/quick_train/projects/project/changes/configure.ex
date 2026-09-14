defmodule QuickTrain.Projects.Project.Changes.Configure do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Datasets.DatasetSchemaVersion
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Projects.{Error, Management}
  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    changeset =
      if changeset.action.name == :configure do
        Enum.reduce(changeset.attributes, changeset, fn
          {key, nil}, changeset -> Ash.Changeset.clear_change(changeset, key)
          _, changeset -> changeset
        end)
      else
        changeset
      end

    Ash.Changeset.before_action(changeset, fn changeset ->
      # Reapply explicit inputs to the locked record, including values equal to
      # the caller's stale copy. Omitted and null draft inputs remain unchanged.
      changeset =
        Ash.Changeset.force_change_attributes(
          changeset,
          Map.reject(changeset.casted_attributes, fn {_key, value} ->
            changeset.action.name == :configure and is_nil(value)
          end)
        )

      organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
      Management.authorize!(context.actor, organization_id)

      if changeset.action.name == :configure and changeset.data.state != :draft,
        do: Error.reject!(:project_not_draft)

      changeset
      |> schema!(organization_id, context.actor)
      |> form!(organization_id, context.actor)
    end)
  end

  defp schema!(changeset, organization_id, actor) do
    if changeset.casted_attributes[:dataset_id] || changeset.casted_attributes[:schema_version_id] do
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
    else
      changeset
    end
  end

  defp form!(changeset, organization_id, actor) do
    if version_id = changeset.casted_attributes[:form_version_id] do
      Management.authorize!(actor, organization_id, "forms.read")

      version =
        FormVersion
        |> Ash.Query.filter(
          id == ^version_id and form.organization_id == ^organization_id and state == :published
        )
        |> Ash.read_one!(authorize?: false)

      if is_nil(version), do: Error.reject!(:invalid_project_configuration)
      Ash.Changeset.force_change_attribute(changeset, :form_id, version.form_id)
    else
      changeset
    end
  end
end
