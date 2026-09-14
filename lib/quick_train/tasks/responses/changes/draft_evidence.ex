defmodule QuickTrain.Tasks.Responses.Changes.DraftEvidence do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.{Attempt, Leases}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  require Ash.Query

  @impl true
  def batch_change(changesets, _opts, _context), do: changesets

  @impl true
  def before_batch(changesets, _opts, _context) do
    ids = attempt_ids(changesets) |> Enum.uniq()

    attempts =
      Attempt
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.sort(project_id: :asc, task_id: :asc, id: :asc)
      |> Ash.read!(authorize?: false, page: false)

    if length(attempts) != length(ids), do: Error.reject!(:forbidden)
    Enum.each(attempts, &lock!/1)
    changesets
  end

  defp attempt_ids([]), do: []

  defp attempt_ids([%{resource: Attempt} | _] = changesets),
    do: Enum.map(changesets, & &1.data.id)

  defp attempt_ids([%{resource: QuestionResponse} | _] = changesets),
    do: Enum.map(changesets, &Ash.Changeset.get_attribute(&1, :attempt_id))

  defp attempt_ids(changesets) do
    ids =
      Enum.map(changesets, &Ash.Changeset.get_attribute(&1, :question_response_id)) |> Enum.uniq()

    outcomes =
      QuestionResponse
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false, page: false)

    if length(outcomes) != length(ids), do: Error.reject!(:forbidden)
    Enum.map(outcomes, & &1.attempt_id)
  end

  defp lock!(initial) do
    project = Access.project!(initial.organization_id, initial.project_id)
    {_task, attempt} = Access.lock_attempt!(project, initial.id)
    if attempt.state == :submitted, do: Error.reject!(:response_submitted)
    unless project.state in [:active, :paused], do: Error.reject!(:project_closed)
    unless attempt.state in Leases.live_states(), do: Error.reject!(:attempt_terminal)

    if DateTime.compare(attempt.deadline, Leases.now!()) != :gt,
      do: Error.reject!(:attempt_expired)

    :ok
  end
end
