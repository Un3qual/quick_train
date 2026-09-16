defmodule QuickTrain.Tasks.Exports.Changes.RequestExport do
  @moduledoc false
  use Ash.Resource.Change

  alias QuickTrain.Accounts.User
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Exports.ResultExport
  alias QuickTrain.Tasks.Workers.ExportResults
  require Ash.Query

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &request(&1, context.actor))

  defp request(changeset, actor) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)
    request_key = Ash.Changeset.get_attribute(changeset, :request_key)
    mode = Ash.Changeset.get_attribute(changeset, :mode)
    project = Access.project!(organization_id, project_id)
    Access.manager!(project, actor, "tasks.results.read")

    # Serialize retries before the insert; the export and its job commit together.
    User
    |> Ash.Query.filter(id == ^actor.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)

    existing =
      ResultExport
      |> Ash.Query.filter(
        project_id == ^project.id and requester_id == ^actor.id and request_key == ^request_key
      )
      |> Ash.read_one!(authorize?: false)

    if existing do
      if existing.mode != mode, do: Error.reject!(:export_request_conflict)
      Ash.Changeset.set_result(changeset, {:ok, existing})
    else
      unless project.state in [:active, :paused, :completed, :archived],
        do: Error.reject!(:project_not_activated)

      changeset
      |> Ash.Changeset.force_change_attribute(:form_version_id, project.form_version_id)
      |> Ash.Changeset.after_action(fn _changeset, export ->
        %{id: export.id} |> ExportResults.new() |> Oban.insert!()
        {:ok, export}
      end)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end
end
