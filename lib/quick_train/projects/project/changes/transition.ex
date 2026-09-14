defmodule QuickTrain.Projects.Project.Changes.Transition do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Projects.{Error, Management, ProjectActivation}
  alias QuickTrain.Tasks.Attempts.Leases
  alias QuickTrain.Tasks.Progress.ProjectCompletion

  @impl true
  def change(changeset, opts, context),
    do: Ash.Changeset.before_action(changeset, &transition(&1, opts, context.actor))

  defp transition(changeset, opts, actor) do
    project = changeset.data
    Management.authorize!(actor, project.organization_id)

    if project.state == opts[:to] do
      Ash.Changeset.set_result(changeset, {:ok, project})
    else
      unless project.state in opts[:from], do: Error.reject!(:invalid_project_transition)

      prepare_transition!(changeset)
    end
  end

  defp prepare_transition!(%{action: %{name: :activate_record}} = changeset) do
    ProjectActivation.validate!(changeset.data)
    Ash.Changeset.force_change_attribute(changeset, :activated_at, DateTime.utc_now())
  end

  defp prepare_transition!(%{action: %{name: :complete_record}} = changeset) do
    cutoff = Leases.now!()
    ProjectCompletion.complete!(changeset.data, cutoff)
    Ash.Changeset.force_change_attribute(changeset, :completed_at, cutoff)
  end
end
