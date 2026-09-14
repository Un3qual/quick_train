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
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Attempts.{Attempt, AttemptInputPresentation, AttemptQuestion, Leases}
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
  @form_context [:presentation_element, :question_definition, :question_option, :label]
  @contexts [:project_input_binding, :dataset_value]
  def kinds, do: Keyword.keys(@resources)
  def resources, do: @resources

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
          {include_form_context, form_count} = select!(export)

          count =
            ExportSelection
            |> Ash.Query.filter(export_id == ^id)
            |> Ash.sum!(:record_count, default: 0, authorize?: false)

          Ash.update!(
            export,
            %{
              state: :writing,
              snapshot_at: Leases.now!(),
              record_count: count + form_count,
              include_form_context: include_form_context,
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

    form_kinds = Enum.filter(wanted, &(&1 in @form_context))

    include_form_context =
      form_kinds != [] and Ash.exists?(eligible(Attempt, export), authorize?: false)

    form_count =
      if include_form_context,
        do: Enum.sum_by(form_kinds, &Ash.count!(form_context(export, &1), authorize?: false)),
        else: 0

    wanted |> Enum.reject(&(&1 in @form_context)) |> Enum.each(&select_kind!(export, &1))
    {include_form_context, form_count}
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

  defp form_context(export, kind) do
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

    range(query, export)
  end

  defp context!(export, :project_input_binding) do
    inputs = context_inputs(export).filter

    ProjectInputBinding
    |> Ash.Query.filter(
      project_id == ^export.project_id and
        exists(issued_inputs, ^inputs and input_slot_id == parent(requirement.input_slot_id))
    )
    |> range(export)
    |> stream()
    |> Stream.map(
      &%{binding_id: &1.id, field_definition_id: &1.field_definition_id, record_count: 1}
    )
    |> pin_all!(export, :project_input_binding)
  end

  defp context!(export, :dataset_value) do
    context_inputs(export)
    |> Ash.Query.load(:revision)
    |> stream()
    |> Stream.chunk_every(100)
    |> Enum.each(&pin_input_values!(export, &1))
  end

  defp context_inputs(export) do
    evidence = ReadAccess.evidence_filter(Attempt, export.mode)

    eligible(TaskInput, export)
    |> Ash.Query.filter(exists(Attempt, task_id == parent(task_id) and ^evidence))
  end

  defp pin_input_values!(export, inputs) do
    slots = Enum.map(inputs, & &1.input_slot_id) |> Enum.uniq()

    ProjectInputBinding
    |> Ash.Query.filter(project_id == ^export.project_id and requirement.input_slot_id in ^slots)
    |> Ash.Query.load(:requirement)
    |> stream()
    |> Stream.chunk_every(100)
    |> Enum.each(&pin_bound_values!(export, inputs, &1))
  end

  defp pin_bound_values!(export, inputs, bindings) do
    sources =
      for input <- inputs,
          binding <- bindings,
          binding.requirement.input_slot_id == input.input_slot_id,
          into: %{} do
        {{input.revision.root_record_id, binding.field_definition_id},
         %{binding_id: binding.id, revision_id: input.revision_id}}
      end

    roots = sources |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    fields = Enum.map(bindings, & &1.field_definition_id) |> Enum.uniq()

    DatasetValue
    |> Ash.Query.filter(
      organization_id == ^export.organization_id and record_id in ^roots and
        field_definition_id in ^fields
    )
    |> range(export)
    |> stream()
    |> Stream.filter(&Map.has_key?(sources, {&1.record_id, &1.field_definition_id}))
    |> Stream.map(fn value ->
      sources
      |> Map.fetch!({value.record_id, value.field_definition_id})
      |> Map.merge(%{
        dataset_value_id: value.id,
        field_definition_id: value.field_definition_id,
        source_record_id: value.record_id,
        record_count: 1
      })
    end)
    |> pin_all!(export, :dataset_value)
  end

  defp pin_group!(export, kind, query, attrs) do
    count = query |> range(export) |> Ash.count!(authorize?: false)
    if count > 0, do: pin!(export, kind, attrs, count)
  end

  defp pin!(export, kind, attrs, count),
    do: pin_all!([Map.put(attrs, :record_count, count)], export, kind)

  defp pin_all!(attributes, export, kind) do
    scope = %{
      export_id: export.id,
      organization_id: export.organization_id,
      project_id: export.project_id,
      form_version_id: export.form_version_id,
      kind: kind
    }

    attributes
    |> Stream.map(&Map.merge(&1, scope))
    |> Ash.bulk_create!(ExportSelection, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true,
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

  def stream(query),
    do: query |> Ash.Query.sort(id: :asc) |> Ash.stream!(batch_size: 100, authorize?: false)

  def rows(export, kind, load) when kind in @form_context do
    if export.include_form_context and
         (is_nil(export.evidence_kind) or export.evidence_kind == Atom.to_string(kind)) do
      export |> form_context(kind) |> Ash.Query.load(load) |> stream()
    else
      []
    end
  end

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
