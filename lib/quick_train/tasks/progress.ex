defmodule QuickTrain.Tasks.Progress do
  @moduledoc false
  alias QuickTrain.Projects.ProjectItem
  alias QuickTrain.Tasks.{Access, AttemptQuestion, Leases, QuestionResponse, QuestionReview}
  alias QuickTrain.Tasks.{Task, TaskInput, TaskItemCoverage, TaskQuestionProgress}
  require Ash.Query

  @counts [:accepted, :pending, :skipped, :rejected, :live, :failures]

  # Callers hold the Task lock; counts and their evidence commit together.
  def change!(project, task, changes) do
    updated =
      Enum.map(rows(task.id), fn row ->
        values =
          Map.new(Map.get(changes, row.question_id, %{}), fn {key, delta} ->
            {key, Map.fetch!(row, key) + delta}
          end)

        update_row!(row, values)
      end)

    update_task!(project, task, updated)
  end

  def reconcile!(organization_id, project_id, task_id) do
    Ash.transact(Task, fn ->
      project = Access.project!(organization_id, project_id)

      task =
        Task
        |> Ash.Query.filter(id == ^task_id and project_id == ^project.id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!(authorize?: false)
        |> Access.found!()

      rows = rows(task.id)
      counts = Map.new(rows, &{&1.question_id, Map.new(@counts, fn key -> {key, 0} end)})
      counts = count_outcomes(task, counts)
      counts = count_attempts(task, counts)
      updated = Enum.map(rows, &update_row!(&1, Map.fetch!(counts, &1.question_id)))
      update_task!(project, task, updated)
    end)
  end

  def reconcile_coverage!(organization_id, project_id) do
    Ash.transact(TaskItemCoverage, fn ->
      project = Access.project!(organization_id, project_id)

      ProjectItem
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(id: :asc)
      |> Ash.stream!(authorize?: false, batch_size: 100)
      |> Enum.each(&reconcile_item!(project, &1))
    end)
  end

  def rows(task_id) do
    TaskQuestionProgress
    |> Ash.Query.filter(task_id == ^task_id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.read!(authorize?: false, page: false)
  end

  def state(project, rows) do
    unmet = Enum.reject(rows, &(&1.accepted >= &1.target))

    cond do
      unmet == [] -> :satisfied
      project.state in [:completed, :archived] -> :cancelled
      Enum.all?(unmet, & &1.attention) -> :needs_attention
      true -> :open
    end
  end

  defp count_outcomes(task, counts) do
    QuestionResponse
    |> Ash.Query.filter(task_id == ^task.id and response.state == :submitted)
    |> Ash.Query.load(:effective_decision)
    |> Ash.stream!(authorize?: false, batch_size: 100)
    |> Enum.reduce(counts, fn outcome, counts ->
      status = QuestionReview.effective_status(outcome)
      counts = increment(counts, outcome.question_id, status)

      if status in [:skipped, :rejected],
        do: increment(counts, outcome.question_id, :failures),
        else: counts
    end)
  end

  defp count_attempts(task, counts) do
    AttemptQuestion
    |> Ash.Query.filter(task_id == ^task.id)
    |> Ash.Query.load(:attempt)
    |> Ash.stream!(authorize?: false, batch_size: 100)
    |> Enum.reduce(counts, fn offered, counts ->
      cond do
        offered.attempt.state in Leases.live_states() ->
          increment(counts, offered.question_id, :live)

        offered.attempt.state in [:expired, :released] ->
          increment(counts, offered.question_id, :failures)

        true ->
          counts
      end
    end)
  end

  defp increment(counts, question_id, field) do
    Map.update!(counts, question_id, &Map.update!(&1, field, fn value -> value + 1 end))
  end

  defp update_row!(row, values) do
    current = Map.merge(row, values)

    attention =
      current.accepted < current.target and current.failures >= current.failure_threshold

    Ash.update!(row, Map.put(values, :attention, attention),
      action: :update_internal,
      authorize?: false
    )
  end

  defp update_task!(project, task, rows) do
    # A caller may have already changed the task earlier in the same locked transaction.
    task = Ash.get!(Task, task.id, authorize?: false)
    target = state(project, rows)

    if task.state == target,
      do: task,
      else: Ash.update!(task, %{state: target}, action: :update_internal, authorize?: false)
  end

  defp reconcile_item!(project, item) do
    attributes = Map.put(Access.scope(project), :project_item_id, item.id)

    Ash.create!(TaskItemCoverage, attributes,
      action: :create_internal,
      authorize?: false,
      upsert?: true,
      upsert_identity: :project_item,
      upsert_fields: [],
      return_skipped_upsert?: true
    )

    coverage =
      TaskItemCoverage
      |> Ash.Query.filter(project_item_id == ^item.id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    count =
      TaskInput
      |> Ash.Query.filter(project_id == ^project.id and project_item_id == ^item.id)
      |> Ash.count!(authorize?: false)

    Ash.update!(coverage, %{exposures: count}, action: :update_internal, authorize?: false)
  end
end
