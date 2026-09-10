defmodule QuickTrain.Forms.Changes.CreatePresentation do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms.Graph

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &create_child/2)
  end

  defp create_child(changeset, element) do
    Graph.create_element_child!(element, changeset.arguments)
    {:ok, element}
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end
end
