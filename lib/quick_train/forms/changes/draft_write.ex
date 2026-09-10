defmodule QuickTrain.Forms.Changes.DraftWrite do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms
  alias QuickTrain.Forms.{Error, FormVersion, Graph}
  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(&lock/1)
    |> Ash.Changeset.after_action(&validate/2)
  end

  defp lock(changeset) do
    version_id =
      if changeset.resource == FormVersion,
        do: changeset.data.id,
        else: Ash.Changeset.get_argument_or_attribute(changeset, :version_id)

    organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
    version = Forms.lock_form_version!(version_id, organization_id, authorize?: false)
    if is_nil(version), do: Error.reject!(:invalid_form_version)
    if version.state != :draft, do: Error.reject!(:version_not_draft)

    changeset
    |> refresh(version)
    |> Ash.Changeset.set_context(%{
      forms_version: version,
      shared: %{forms_version_id: version.id}
    })
  rescue
    error in Ash.Error.Invalid -> Ash.Changeset.add_error(changeset, error)
  end

  defp validate(changeset, result) do
    Graph.validate!(changeset.context.forms_version, :draft)
    {:ok, result}
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp refresh(%{action_type: :create} = changeset, _version), do: changeset

  defp refresh(changeset, version) do
    record =
      if changeset.resource == FormVersion do
        version
      else
        changeset.resource
        |> Ash.Query.filter(id == ^changeset.data.id and version_id == ^version.id)
        |> Ash.read_one!(authorize?: false)
      end

    if is_nil(record), do: Error.reject!(:invalid_definition)

    # Reapply Ash's cast input after reloading: an explicit value equal to stale data
    # must still be written, while omitted attributes retain the current value.
    %{changeset | data: record}
    |> Ash.Changeset.force_change_attributes(changeset.casted_attributes)
  end
end
