defmodule QuickTrain.Tasks.Progress do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Projects.ProjectItem
  alias QuickTrain.Tasks.{Access, Task, TaskInput}
  alias QuickTrain.Tasks.Attempts.{AttemptQuestion, Leases}
  alias QuickTrain.Tasks.Progress.{TaskItemCoverage, TaskQuestionProgress}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.QuestionReview
  require Ash.Query

  @counts [:accepted, :pending, :skipped, :rejected, :live, :failures]

  @impl true
  def run(input, opts, _context) do
    args = input.arguments

    if opts[:coverage?] do
      reconcile_coverage!(args.organization_id, args.project_id)
    else
      {:ok, reconcile!(args.organization_id, args.project_id, args.task_id)}
    end
  end

  # Callers hold the Task lock; counts and their evidence commit together.
  def change!(task, changes) do
    task.id
    |> rows()
    |> Enum.map(&change_row(&1, Map.get(changes, &1.question_id, %{})))
    |> update_rows!()
  end

  defp reconcile!(organization_id, project_id, task_id) do
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

    rows
    |> Enum.map(&{&1, Map.fetch!(counts, &1.question_id)})
    |> update_rows!()

    Ash.load!(task, :state, authorize?: false)
  end

  defp reconcile_coverage!(organization_id, project_id) do
    project = Access.project!(organization_id, project_id)

    ProjectItem
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.stream!(authorize?: false, batch_size: 100)
    |> Enum.each(&reconcile_item!(project, &1))
  end

  def rows(task_id) do
    TaskQuestionProgress
    |> Ash.Query.filter(task_id == ^task_id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.read!(authorize?: false, page: false)
  end

  defp count_outcomes(task, counts) do
    QuestionResponse
    |> Ash.Query.filter(task_id == ^task.id and attempt.state == :submitted)
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

  defp change_row(row, deltas) when map_size(deltas) == 0, do: {row, %{}}

  defp change_row(row, deltas) do
    values = Map.new(deltas, fn {key, delta} -> {key, Map.fetch!(row, key) + delta} end)
    {row, values}
  end

  defp update_rows!(updates) do
    updates
    |> Enum.reject(fn {row, values} ->
      Enum.all?(values, fn {key, value} -> Map.fetch!(row, key) == value end)
    end)
    |> Ash.update_many!(TaskQuestionProgress, :update_internal,
      strategy: [:atomic],
      authorize?: false,
      return_records?: false
    )

    :ok
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
