defmodule QuickTrain.Forms.Changes.CopyPublished do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms.{Error, FormVersion, Graph}
  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(&prepare_source/1)
    |> Ash.Changeset.after_action(&copy_graph/2)
  end

  defp prepare_source(changeset) do
    form_id = Ash.Changeset.get_attribute(changeset, :form_id)
    source_id = Ash.Changeset.get_argument(changeset, :source_version_id)

    source =
      FormVersion
      |> Ash.Query.filter(id == ^source_id and form_id == ^form_id and state == :published)
      |> Ash.read_one!(authorize?: false)

    if is_nil(source), do: Error.reject!(:invalid_copy_source)

    changeset
    |> Ash.Changeset.force_change_attributes(Map.take(source, [:title, :description]))
    |> Ash.Changeset.set_context(%{forms_copy_source: source})
  rescue
    error in Ash.Error.Invalid -> Ash.Changeset.add_error(changeset, error)
  end

  defp copy_graph(changeset, version) do
    Graph.copy!(changeset.context.forms_copy_source, version)
    {:ok, version}
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end
end
