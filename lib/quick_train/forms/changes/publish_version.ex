defmodule QuickTrain.Forms.Changes.PublishVersion do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms
  alias QuickTrain.Forms.{Error, Graph}

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.before_action(changeset, &publish/1)

  defp publish(changeset) do
    organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
    version = Forms.lock_form_version!(changeset.data.id, organization_id, authorize?: false)
    if is_nil(version), do: Error.reject!(:invalid_form_version)

    changeset = %{changeset | data: version}

    if version.state == :published do
      Ash.Changeset.set_result(changeset, {:ok, version})
    else
      Graph.validate!(version, :published)

      Ash.Changeset.force_change_attributes(changeset, %{
        state: :published,
        published_at: DateTime.utc_now()
      })
    end
  rescue
    error in Ash.Error.Invalid -> Ash.Changeset.add_error(changeset, error)
  end
end
