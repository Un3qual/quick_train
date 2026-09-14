defmodule QuickTrain.Tasks.Changes.DraftEvidence do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Tasks.{Access, Error, Leases, QuestionResponse, Response}

  @impl true
  def change(changeset, _opts, _context), do: Ash.Changeset.before_action(changeset, &lock!/1)

  defp lock!(changeset) do
    response_id =
      cond do
        changeset.resource == Response ->
          changeset.data.id

        changeset.resource == QuestionResponse ->
          Ash.Changeset.get_attribute(changeset, :response_id)

        true ->
          id = Ash.Changeset.get_attribute(changeset, :question_response_id)
          Ash.get!(QuestionResponse, id, authorize?: false).response_id
      end

    initial = Ash.get!(Response, response_id, authorize?: false)
    project = Access.project!(initial.organization_id, initial.project_id)
    {_task, attempt} = Access.lock_attempt!(project, initial.attempt_id)
    response = Access.response!(attempt)
    if response.state != :draft, do: Error.reject!(:response_submitted)
    unless project.state in [:active, :paused], do: Error.reject!(:project_closed)
    unless attempt.state in Leases.live_states(), do: Error.reject!(:attempt_terminal)

    if DateTime.compare(attempt.deadline, Leases.now!()) != :gt,
      do: Error.reject!(:attempt_expired)

    changeset
  end
end
