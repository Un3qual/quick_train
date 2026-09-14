defmodule QuickTrain.Tasks.Exports.Snapshot do
  alias QuickTrain.Datasets.DatasetItemRevision
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.Labels.Label
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition
  alias QuickTrain.Forms.Questions.QuestionOption
  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Repo
  alias QuickTrain.Tasks.Access
  alias QuickTrain.Tasks.Attempt
  alias QuickTrain.Tasks.AttemptInputPresentation
  alias QuickTrain.Tasks.AttemptQuestion
  alias QuickTrain.Tasks.Error
  alias QuickTrain.Tasks.ExportSelection
  alias QuickTrain.Tasks.Leases
  alias QuickTrain.Tasks.QuestionResponse
  alias QuickTrain.Tasks.ReadAccess
  alias QuickTrain.Tasks.ResultExport
  alias QuickTrain.Tasks.ReviewDecision
  alias QuickTrain.Tasks.StaticOptionAnswer
  alias QuickTrain.Tasks.Task
  alias QuickTrain.Tasks.TaskInput
  alias QuickTrain.Tasks.TaskInputAnswer
  alias QuickTrain.Tasks.TextSpan
  @moduledoc false
  require Ash.Query
  import Ash.Expr

  @resources [
    task: Task,
    task_input: TaskInput,
    attempt: Attempt,
    attempt_question: AttemptQuestion,
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
  @contexts [
    :presentation_element,
    :question_definition,
    :question_option,
    :label,
    :project_input_binding,
    :dataset_value
  ]
  def kinds, do: Keyword.keys(@resources)
  def resources, do: @resources

  def seal(id) do
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

          count =
            ExportSelection
            |> Ash.Query.filter(export_id == ^id)
            |> Ash.sum!(:record_count, default: 0, authorize?: false)

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
    wanted =
      if export.evidence_kind, do: [String.to_existing_atom(export.evidence_kind)], else: kinds()

    Enum.each(wanted, fn kind -> select_kind!(export, kind) end)
  end

  defp select_kind!(export, kind) when kind in [:task, :task_input] do
    eligible(Task, export)
    |> stream()
    |> Enum.each(fn task ->
      query =
        if kind == :task,
          do: Ash.Query.filter(Task, id == ^task.id),
          else: Ash.Query.filter(TaskInput, task_id == ^task.id)

      pin_group!(export, kind, query, %{task_id: task.id})
    end)
  end

  defp select_kind!(export, kind)
       when kind in [:attempt, :attempt_question, :attempt_input_presentation] do
    eligible(Attempt, export)
    |> stream()
    |> Enum.each(fn attempt ->
      resource = Keyword.fetch!(@resources, kind)

      query =
        if kind == :attempt,
          do: Ash.Query.filter(resource, id == ^attempt.id),
          else: Ash.Query.filter(resource, attempt_id == ^attempt.id)

      pin_group!(export, kind, query, %{task_id: attempt.task_id, attempt_id: attempt.id})
    end)
  end

  defp select_kind!(export, kind)
       when kind in [
              :question_response,
              :static_option_answer,
              :task_input_answer,
              :text_span,
              :review_decision
            ] do
    eligible(QuestionResponse, export)
    |> Ash.Query.load(:effective_decision)
    |> stream()
    |> Enum.each(&pin_outcome!(export, kind, &1))
  end

  defp select_kind!(export, kind) when kind in @contexts do
    # Context eligibility is independent of the output-kind filter. It follows
    # only eligible attempts and their pinned form/input graph.
    if eligible(Attempt, export) |> Ash.exists?(authorize?: false) do
      context!(export, kind)
    end
  end

  defp pin_outcome!(export, kind, outcome) do
    decision = outcome.effective_decision

    attrs = %{
      task_id: outcome.task_id,
      question_id: outcome.question_id,
      question_response_id: outcome.id,
      decision_id: decision && decision.id
    }

    if kind == :review_decision do
      query = ReviewDecision |> Ash.Query.filter(question_response_id == ^outcome.id)

      query =
        if export.mode == :accepted,
          do: Ash.Query.filter(query, id == ^decision.id),
          else: query

      query
      |> range(export)
      |> stream()
      |> Enum.each(fn row -> pin!(export, kind, Map.put(attrs, :decision_id, row.id), 1) end)
    else
      resource = Keyword.fetch!(@resources, kind)

      query =
        if kind == :question_response,
          do: Ash.Query.filter(resource, id == ^outcome.id),
          else: Ash.Query.filter(resource, question_response_id == ^outcome.id)

      pin_group!(export, kind, query, attrs)
    end
  end

  defp context!(export, kind)
       when kind in [:presentation_element, :question_definition, :question_option, :label] do
    resource = Keyword.fetch!(@resources, kind)
    query = Ash.Query.filter(resource, version_id == ^export.form_version_id)

    query =
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

    query
    |> range(export)
    |> stream()
    |> Enum.each(fn row ->
      attrs =
        case kind do
          :presentation_element -> %{presentation_element_id: row.id}
          :question_definition -> %{question_id: row.id}
          :question_option -> %{question_id: row.question_id, question_option_id: row.id}
          :label -> %{label_id: row.id}
        end

      pin!(export, kind, attrs, 1)
    end)
  end

  defp context!(export, kind) do
    evidence = ReadAccess.evidence_filter(Attempt, export.mode)

    eligible(TaskInput, export)
    |> Ash.Query.filter(exists(Attempt, task_id == parent(task_id) and ^evidence))
    |> stream()
    |> Enum.each(&pin_input_context!(export, kind, &1))
  end

  defp pin_input_context!(export, kind, input) do
    ProjectInputBinding
    |> Ash.Query.filter(
      project_id == ^export.project_id and requirement.input_slot_id == ^input.input_slot_id
    )
    |> stream()
    |> Enum.each(&pin_binding!(export, kind, input, &1))
  end

  defp pin_binding!(export, :project_input_binding, _input, binding) do
    if within?(binding.id, export),
      do:
        pin!(
          export,
          :project_input_binding,
          %{binding_id: binding.id, field_definition_id: binding.field_definition_id},
          1
        )
  end

  defp pin_binding!(export, :dataset_value, input, binding) do
    revision = Ash.get!(DatasetItemRevision, input.revision_id, authorize?: false)

    DatasetValue
    |> Ash.Query.filter(
      organization_id == ^export.organization_id and record_id == ^revision.root_record_id and
        field_definition_id == ^binding.field_definition_id
    )
    |> range(export)
    |> stream()
    |> Enum.each(fn value ->
      pin!(
        export,
        :dataset_value,
        %{
          binding_id: binding.id,
          field_definition_id: binding.field_definition_id,
          dataset_value_id: value.id,
          revision_id: revision.id,
          source_record_id: revision.root_record_id
        },
        1
      )
    end)
  end

  defp pin_group!(export, kind, query, attrs) do
    count = query |> range(export) |> Ash.count!(authorize?: false)
    if count > 0, do: pin!(export, kind, attrs, count)
  end

  defp pin!(export, kind, attrs, count) do
    attrs =
      Map.merge(attrs, %{
        export_id: export.id,
        organization_id: export.organization_id,
        project_id: export.project_id,
        form_version_id: export.form_version_id,
        kind: kind,
        record_count: count
      })

    Ash.create!(ExportSelection, attrs,
      action: :create_internal,
      authorize?: false,
      upsert?: true,
      upsert_identity: if(kind == :dataset_value, do: :source_value, else: :membership),
      upsert_fields: []
    )
  end

  def eligible(resource, export) do
    evidence = ReadAccess.evidence_filter(resource, export.mode)

    query =
      Ash.Query.filter(
        resource,
        organization_id == ^export.organization_id and project_id == ^export.project_id and
          ^evidence
      )

    field = if resource == Task, do: :id, else: :task_id

    query =
      if export.task_id_from,
        do: Ash.Query.filter(query, ^[{field, [greater_than_or_equal: export.task_id_from]}]),
        else: query

    if export.task_id_to,
      do: Ash.Query.filter(query, ^[{field, [less_than_or_equal: export.task_id_to]}]),
      else: query
  end

  def range(query, export) do
    query =
      if export.evidence_id_from,
        do: Ash.Query.filter(query, id >= ^export.evidence_id_from),
        else: query

    if export.evidence_id_to,
      do: Ash.Query.filter(query, id <= ^export.evidence_id_to),
      else: query
  end

  defp within?(id, export),
    do:
      (is_nil(export.evidence_id_from) or id >= export.evidence_id_from) and
        (is_nil(export.evidence_id_to) or id <= export.evidence_id_to)

  def stream(query),
    do: query |> Ash.Query.sort(id: :asc) |> Ash.stream!(batch_size: 100, authorize?: false)

  def rows(export, kind, load) do
    membership = membership(export, kind)

    Keyword.fetch!(@resources, kind)
    |> Ash.Query.filter(^membership)
    |> range(export)
    |> Ash.Query.load(load)
    |> stream()
  end

  for {kind, field, parent_field} <- [
        {:task, :task_id, :id},
        {:task_input, :task_id, :task_id},
        {:attempt, :attempt_id, :id},
        {:attempt_question, :attempt_id, :attempt_id},
        {:attempt_input_presentation, :attempt_id, :attempt_id},
        {:question_response, :question_response_id, :id},
        {:static_option_answer, :question_response_id, :question_response_id},
        {:task_input_answer, :question_response_id, :question_response_id},
        {:text_span, :question_response_id, :question_response_id},
        {:review_decision, :decision_id, :id},
        {:presentation_element, :presentation_element_id, :id},
        {:question_definition, :question_id, :id},
        {:question_option, :question_option_id, :id},
        {:label, :label_id, :id},
        {:project_input_binding, :binding_id, :id},
        {:dataset_value, :dataset_value_id, :id}
      ] do
    defp membership(export, unquote(kind)) do
      expr(
        exists(
          ExportSelection,
          export_id == ^export.id and kind == ^unquote(kind) and
            ^ref(unquote(field)) == parent(^ref(unquote(parent_field)))
        )
      )
    end
  end
end
