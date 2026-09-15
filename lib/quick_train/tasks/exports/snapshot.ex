defmodule QuickTrain.Tasks.Exports.Snapshot do
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.Labels.Label
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Forms.Questions.QuestionOption
  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.{Access, Error, Task, TaskInput}
  alias QuickTrain.Tasks.Attempts.{Attempt, AttemptInputPresentation, Leases}
  alias QuickTrain.Tasks.Exports.{ExportSelection, ResultExport}

  alias QuickTrain.Tasks.Responses.{
    QuestionResponse,
    StaticOptionAnswer,
    TaskInputAnswer,
    TextSpan
  }

  alias QuickTrain.Tasks.Reviews.ReviewDecision
  @moduledoc false
  require Ash.Query
  import Ash.Expr

  @resources [
    task: Task,
    task_input: TaskInput,
    attempt: Attempt,
    attempt_input_presentation: AttemptInputPresentation,
    question_response: QuestionResponse,
    static_option_answer: StaticOptionAnswer,
    task_input_answer: TaskInputAnswer,
    text_span: TextSpan,
    review_decision: ReviewDecision,
    presentation_element: PresentationElement,
    question_definition: QuestionDefinition,
    question_option: QuestionOption,
    label: Label,
    project_input_binding: ProjectInputBinding,
    dataset_value: DatasetValue
  ]
  @form_context [:presentation_element, :question_definition, :question_option, :label]
  def kinds, do: Keyword.keys(@resources)

  @impl true
  def run(%{arguments: %{id: id}}, _opts, _context) do
    Ash.transact([ResultExport, ExportSelection], fn ->
      # This must be the transaction's first statement: every page sees one
      # committed MVCC snapshot, including submissions concurrent with selection.
      Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

      export =
        ResultExport
        |> Ash.Query.filter(id == ^id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!(authorize?: false)
        |> Access.found!()

      cond do
        export.snapshot_at ->
          export

        export.state == :failed ->
          Error.reject!(:export_snapshot_failed)

        true ->
          project = Access.project!(export.organization_id, export.project_id)
          Access.manager!(project, %{id: export.requester_id}, "tasks.results.read")
          select!(export)
          count = Enum.sum_by(kinds(), &Ash.count!(query(export, &1), authorize?: false))

          Ash.update!(
            export,
            %{
              state: :writing,
              snapshot_at: Leases.now!(),
              record_count: count,
              error_code: nil
            },
            action: :update_internal,
            authorize?: false
          )
      end
    end)
  end

  defp select!(export) do
    QuestionResponse
    |> Ash.Query.filter(
      project_id == ^export.project_id and attempt.state == :submitted and
        (^export.mode == :audit or effective_verdict == :accept)
    )
    |> Ash.Query.load(:effective_decision)
    |> stream()
    |> Stream.map(fn outcome ->
      %{
        export_id: export.id,
        organization_id: export.organization_id,
        project_id: export.project_id,
        form_version_id: export.form_version_id,
        task_id: outcome.task_id,
        question_id: outcome.question_id,
        question_response_id: outcome.id,
        decision_id: outcome.effective_decision && outcome.effective_decision.id
      }
    end)
    |> Ash.bulk_create!(ExportSelection, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )
  end

  defp form_context(export, kind) do
    resource = Keyword.fetch!(@resources, kind)
    query = Ash.Query.filter(resource, version_id == ^export.form_version_id)

    if kind == :label do
      Ash.Query.filter(
        query,
        exists(
          AnnotationConstraints,
          version_id == ^export.form_version_id and label_set_id == parent(label_set_id)
        )
      )
    else
      query
    end
  end

  defp stream(query),
    do: query |> Ash.Query.sort(id: :asc) |> Ash.stream!(batch_size: 100, authorize?: false)

  def rows(export, kind, load), do: export |> query(kind) |> Ash.Query.load(load) |> stream()

  defp query(export, kind) when kind in @form_context do
    export
    |> form_context(kind)
    |> Ash.Query.filter(exists(ExportSelection, export_id == ^export.id))
  end

  defp query(export, :project_input_binding) do
    inputs = query(export, :task_input).filter

    ProjectInputBinding
    |> Ash.Query.filter(
      project_id == ^export.project_id and
        exists(
          TaskInput,
          project_id == parent(project_id) and ^inputs and
            input_slot_id == parent(requirement.input_slot_id)
        )
    )
  end

  defp query(export, :dataset_value) do
    inputs = query(export, :task_input).filter

    DatasetValue
    |> Ash.Query.filter(
      organization_id == ^export.organization_id and
        exists(
          TaskInput,
          ^inputs and revision.root_record_id == parent(record_id) and
            exists(
              project.bindings,
              field_definition_id == parent(parent(field_definition_id)) and
                requirement.input_slot_id == parent(input_slot_id)
            )
        )
    )
  end

  defp query(export, :review_decision) do
    ReviewDecision
    |> Ash.Query.filter(
      exists(
        ExportSelection,
        export_id == ^export.id and question_response_id == parent(question_response_id) and
          ((^export.mode == :accepted and decision_id == parent(id)) or
             (^export.mode == :audit and decision.number >= parent(number)))
      )
    )
  end

  for {kind, path, field, parent_field} <- [
        {:task, [], :task_id, :id},
        {:task_input, [], :task_id, :task_id},
        {:attempt, [:question_response], :attempt_id, :id},
        {:attempt_input_presentation, [:question_response], :attempt_id, :attempt_id},
        {:question_response, [], :question_response_id, :id},
        {:static_option_answer, [], :question_response_id, :question_response_id},
        {:task_input_answer, [], :question_response_id, :question_response_id},
        {:text_span, [], :question_response_id, :question_response_id}
      ] do
    defp query(export, unquote(kind)) do
      membership =
        expr(
          exists(
            ExportSelection,
            export_id == ^export.id and
              ^ref(unquote(path), unquote(field)) == parent(^ref(unquote(parent_field)))
          )
        )

      Keyword.fetch!(@resources, unquote(kind)) |> Ash.Query.filter(^membership)
    end
  end
end
