defmodule QuickTrain.Tasks.Responses.Changes.DraftEvidence do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Attempts.Leases
  alias QuickTrain.Tasks.Responses.{QuestionResponse, Response}
  require Ash.Query

  @impl true
  def batch_change(changesets, _opts, _context), do: changesets

  @impl true
  def before_batch(changesets, _opts, _context) do
    ids = response_ids(changesets) |> Enum.uniq()

    responses =
      Response
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.sort(project_id: :asc, task_id: :asc, id: :asc)
      |> Ash.read!(authorize?: false, page: false)

    if length(responses) != length(ids), do: Error.reject!(:forbidden)
    Enum.each(responses, &lock!/1)
    changesets
  end

  defp response_ids([]), do: []

  defp response_ids([%{resource: Response} | _] = changesets),
    do: Enum.map(changesets, & &1.data.id)

  defp response_ids([%{resource: QuestionResponse} | _] = changesets),
    do: Enum.map(changesets, &Ash.Changeset.get_attribute(&1, :response_id))

  defp response_ids(changesets) do
    ids =
      Enum.map(changesets, &Ash.Changeset.get_attribute(&1, :question_response_id)) |> Enum.uniq()

    outcomes =
      QuestionResponse
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false, page: false)

    if length(outcomes) != length(ids), do: Error.reject!(:forbidden)
    Enum.map(outcomes, & &1.response_id)
  end

  defp lock!(initial) do
    project = Access.project!(initial.organization_id, initial.project_id)
    {_task, attempt} = Access.lock_attempt!(project, initial.attempt_id)
    response = Access.response!(attempt)
    if response.state != :draft, do: Error.reject!(:response_submitted)
    unless project.state in [:active, :paused], do: Error.reject!(:project_closed)
    unless attempt.state in Leases.live_states(), do: Error.reject!(:attempt_terminal)

    if DateTime.compare(attempt.deadline, Leases.now!()) != :gt,
      do: Error.reject!(:attempt_expired)

    :ok
  end
end
