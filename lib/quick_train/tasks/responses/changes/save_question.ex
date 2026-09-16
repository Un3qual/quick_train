defmodule QuickTrain.Tasks.Responses.Changes.SaveQuestion do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms
  alias QuickTrain.Tasks.Attempts.Leases

  alias QuickTrain.Tasks.{Access, Error}

  alias QuickTrain.Tasks.Responses.{AnswerValidation, QuestionResponse}

  require Ash.Query

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_action(changeset, &save(&1, context.actor))

  defp save(changeset, actor) do
    args = changeset.arguments
    project = Access.project!(changeset.data.organization_id, changeset.data.project_id)
    {task, attempt} = Access.lock_attempt!(project, changeset.data.id)
    changeset = %{changeset | data: attempt}
    Access.owner!(project, attempt, actor)
    if attempt.revision != args.expected_revision, do: Error.reject!(:stale_response)

    question =
      Forms.get_form_question_definition!(project.organization_id, args.question_id,
        query: [filter: [version_id: project.form_version_id]],
        not_found_error?: false,
        authorize?: false
      )

    unless question, do: Error.reject!(:question_not_offered)
    normalized = AnswerValidation.validate!(project, task, question, args.answer, :draft)

    AnswerValidation.skip_policies!(project, [
      Map.put(normalized.attributes, :question_id, question.id)
    ])

    remove_previous!(attempt, question.id)
    scope = Map.merge(Access.scope(project), %{task_id: task.id, question_id: question.id})

    outcome =
      Ash.Changeset.for_create(
        QuestionResponse,
        :create_internal,
        Map.merge(scope, Map.put(normalized.attributes, :attempt_id, attempt.id)),
        authorize?: false
      )

    [
      static_options: Enum.map(normalized.option_ids, &%{option_id: &1}),
      input_answers: normalized.inputs,
      text_spans: normalized.spans
    ]
    |> Enum.reduce(outcome, fn {relationship, children}, outcome ->
      Ash.Changeset.manage_relationship(
        outcome,
        relationship,
        Enum.map(children, &Map.merge(scope, &1)),
        type: :create,
        on_no_match: {:create, :create_internal},
        authorize?: false,
        bulk?: true
      )
    end)
    |> Ash.create!()

    Access.owner!(project, attempt, actor)

    if attempt.state in [:claimed, :assigned],
      do:
        Ash.Changeset.force_change_attributes(changeset, %{
          state: :in_progress,
          started_at: Leases.now!()
        }),
      else: changeset
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden] -> Ash.Changeset.add_error(changeset, error)
  end

  defp remove_previous!(attempt, question_id) do
    prior =
      QuestionResponse
      |> Ash.Query.filter(attempt_id == ^attempt.id and question_id == ^question_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    if prior, do: Ash.destroy!(prior, action: :destroy_internal, authorize?: false)
  end
end
