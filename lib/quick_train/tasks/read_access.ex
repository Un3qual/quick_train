defmodule QuickTrain.Tasks.ReadAccess do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization.RoleAssignment

  alias QuickTrain.Tasks.{
    Attempt,
    AttemptInputPresentation,
    AttemptQuestion,
    QuestionResponse,
    Response,
    ReviewDecision,
    StaticOptionAnswer,
    Task,
    TaskInput,
    TaskInputAnswer,
    TaskItemCoverage,
    TaskQuestionProgress,
    TextSpan
  }

  import Ash.Expr

  def describe(_), do: "current access to issued task evidence"

  def filter(%{id: _} = actor, %{resource: resource, query: query}, _opts) do
    cond do
      query.action.name == :read and not task_relationship?(query) ->
        false

      get_in(query.context, [:shared, :task_result_mode]) in [:accepted, :audit] ->
        authority = result_authority(actor)
        evidence = evidence_filter(resource, query.context.shared.task_result_mode)
        expr(^authority and ^evidence)

      true ->
        authorized_filter(resource, actor, :audit, receipt?(query))
    end
  end

  def filter(_, _, _), do: false

  defp task_relationship?(query) do
    case query.context[:accessing_from] do
      %{source: source} -> String.starts_with?(Atom.to_string(source), "Elixir.QuickTrain.Tasks.")
      _ -> false
    end
  end

  defp receipt?(query),
    do:
      match?(
        %{source: QuickTrain.Tasks.Receipt, name: :questions},
        query.context[:accessing_from]
      )

  # This is one SQL eligibility predicate; splitting it hides the audience alternatives.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def eligible_attempt(%{id: id}) do
    expr(
      worker_id == ^id and worker.status == "active" and organization.status == "active" and
        not exists(project.worker_access, user_id == ^id and disposition == :block) and
        ((project.audience in [:organization_members, :both] and
            exists(project.organization.memberships, user_id == ^id and status == "active")) or
           (project.audience in [:external_users, :both] and
              (project.external_access == :open or
                 exists(project.worker_access, user_id == ^id and disposition == :allow))))
    )
  end

  def live_attempt(actor) do
    eligible = eligible_attempt(actor)

    expr(
      ^eligible and state in [:claimed, :assigned, :in_progress] and
        deadline > fragment("clock_timestamp()") and
        project.state in [:active, :paused]
    )
  end

  def result_authority(%{id: id}) do
    expr(
      exists(
        RoleAssignment,
        organization_id == parent(organization_id) and user_id == ^id and
          user.status == "active" and organization.status == "active" and
          exists(role.role_capabilities, capability.key == "tasks.results.read") and
          exists(organization.memberships, user_id == ^id and status == "active")
      )
    )
  end

  def authorized_filter(resource, actor, mode \\ :audit, receipt? \\ false) do
    worker = worker_filter(resource, actor, receipt?)
    authority = result_authority(actor)
    evidence = evidence_filter(resource, mode)
    expr(^worker or (^authority and ^evidence))
  end

  defp worker_filter(AttemptQuestion, actor, true) do
    eligible = eligible_attempt(actor)
    expr(exists(attempt, ^eligible))
  end

  defp worker_filter(resource, actor, _receipt?) do
    live_worker_filter(resource, live_attempt(actor))
  end

  defp live_worker_filter(Task, live), do: expr(exists(Attempt, task_id == parent(id) and ^live))

  defp live_worker_filter(TaskInput, live),
    do: expr(exists(Attempt, task_id == parent(task_id) and ^live))

  defp live_worker_filter(Attempt, live), do: live

  defp live_worker_filter(resource, live)
       when resource in [AttemptQuestion, AttemptInputPresentation, Response],
       do: expr(exists(attempt, ^live))

  defp live_worker_filter(QuestionResponse, live), do: expr(exists(response.attempt, ^live))

  defp live_worker_filter(resource, live)
       when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan],
       do: expr(exists(question_response.response.attempt, ^live))

  defp live_worker_filter(resource, _live)
       when resource in [ReviewDecision, TaskQuestionProgress, TaskItemCoverage], do: false

  def evidence_filter(resource, :accepted) do
    base = audit_filter(resource)
    accepted = accepted_filter(resource)
    expr(^base and ^accepted)
  end

  def evidence_filter(resource, _mode), do: audit_filter(resource)

  defp audit_filter(resource) when resource in [Task, TaskInput, TaskQuestionProgress], do: true
  defp audit_filter(TaskItemCoverage), do: expr(exists(issued_inputs, true))
  defp audit_filter(Attempt), do: expr(state in [:submitted, :expired, :released, :cancelled])

  defp audit_filter(resource) when resource in [AttemptQuestion, AttemptInputPresentation],
    do: expr(attempt.state in [:submitted, :expired, :released, :cancelled])

  defp audit_filter(Response), do: expr(state == :submitted)
  defp audit_filter(QuestionResponse), do: expr(response.state == :submitted)

  defp audit_filter(resource)
       when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan, ReviewDecision],
       do: expr(question_response.response.state == :submitted)

  defp accepted_filter(Task),
    do: expr(exists(outcomes, response.state == :submitted and effective_verdict == :accept))

  defp accepted_filter(resource) when resource in [TaskInput, TaskQuestionProgress],
    do: expr(exists(task.outcomes, response.state == :submitted and effective_verdict == :accept))

  defp accepted_filter(TaskItemCoverage),
    do:
      expr(
        exists(
          issued_inputs.task.outcomes,
          response.state == :submitted and effective_verdict == :accept
        )
      )

  defp accepted_filter(Attempt), do: expr(exists(response.outcomes, effective_verdict == :accept))

  defp accepted_filter(resource) when resource in [AttemptQuestion, AttemptInputPresentation],
    do: expr(exists(attempt.response.outcomes, effective_verdict == :accept))

  defp accepted_filter(Response), do: expr(exists(outcomes, effective_verdict == :accept))
  defp accepted_filter(QuestionResponse), do: expr(effective_verdict == :accept)

  defp accepted_filter(resource) when resource in [StaticOptionAnswer, TaskInputAnswer, TextSpan],
    do: expr(question_response.effective_verdict == :accept)

  defp accepted_filter(ReviewDecision),
    do:
      expr(
        question_response.effective_verdict == :accept and
          number == question_response.effective_decision_number
      )
end

defmodule QuickTrain.Tasks.ReadAccess.Prepare do
  @moduledoc false
  use Ash.Resource.Preparation
  alias QuickTrain.Tasks.ReadAccess
  require Ash.Query

  def prepare(query, opts, _context) do
    mode = Keyword.fetch!(opts, :mode)
    filter = ReadAccess.evidence_filter(query.resource, mode)

    query =
      query
      |> Ash.Query.filter(^filter)
      |> Ash.Query.set_context(%{shared: %{task_result_mode: mode}})

    case query.action.pagination do
      %{stable_sort: sort} when is_list(sort) ->
        query |> Ash.Query.sort(sort) |> Ash.Query.ensure_selected(Keyword.keys(sort))

      _ ->
        query
    end
  end
end

defmodule QuickTrain.Tasks.ReadActions do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Assets.{AssetAccessResult, AssetSummary, Storage}
  alias QuickTrain.Datasets.{DatasetItemRevision, DatasetValue}
  alias QuickTrain.Forms.Inputs.InputFieldRequirement
  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Tasks.{Access, Attempt, BoundValue, Error, Leases, Receipt, TaskInput}
  require Ash.Query

  def run(input, _opts, context) do
    if is_nil(context.actor), do: Error.reject!(:forbidden)

    if input.action.name == :source_download do
      source_download(input.arguments, context.actor)
    else
      QuickTrain.Repo.transaction(fn -> execute(input, context.actor) end)
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown, Postgrex.Error] ->
      {:error, error}
  end

  defp execute(%{action: %{name: action}, arguments: args}, actor)
       when action in [:work_bundle, :receipt] do
    project = Access.project!(args.organization_id, args.project_id)

    attempt =
      Attempt
      |> Ash.Query.filter(id == ^args.attempt_id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)
      |> Access.found!()

    Access.owner!(project, attempt, actor, action == :work_bundle)

    if action == :receipt do
      if attempt.state in Leases.live_states(), do: Error.reject!(:attempt_not_terminal)
      struct!(Receipt, Map.take(attempt, [:id, :state, :started_at, :terminal_at, :inserted_at]))
    else
      attempt
    end
  end

  defp execute(%{action: %{name: :bound_value}, arguments: args}, actor) do
    {project, input, _deadline} = authorize_input!(args, actor)
    bound_value!(project, input, args.requirement_id)
  end

  def authorize_input!(args, actor) do
    project = Access.project!(args.organization_id, args.project_id)

    input =
      TaskInput
      |> Ash.Query.filter(id == ^args.task_input_id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)
      |> Access.found!()

    deadline =
      if args[:attempt_id] do
        attempt =
          Attempt
          |> Ash.Query.filter(
            id == ^args.attempt_id and task_id == ^input.task_id and project_id == ^project.id
          )
          |> Ash.read_one!(authorize?: false)
          |> Access.found!()

        Access.owner!(project, attempt, actor)
        attempt.deadline
      else
        Access.manager!(project, actor, "tasks.results.read")
        nil
      end

    {project, input, deadline}
  end

  def bound_value!(project, input, requirement_id) do
    binding =
      ProjectInputBinding
      |> Ash.Query.filter(
        project_id == ^project.id and requirement_id == ^requirement_id and
          requirement.input_slot_id == ^input.input_slot_id
      )
      |> Ash.read_one!(authorize?: false)
      |> Access.found!()

    revision =
      Ash.get!(DatasetItemRevision, input.revision_id, authorize?: false)

    requirement = Ash.get!(InputFieldRequirement, requirement_id, authorize?: false)

    value =
      DatasetValue
      |> Ash.Query.filter(
        record_id == ^revision.root_record_id and
          field_definition_id == ^binding.field_definition_id
      )
      |> Ash.read_one!(authorize?: false)

    asset =
      if value do
        loaded = Ash.load!(value, [asset_value: :asset], authorize?: false)
        if loaded.asset_value, do: AssetSummary.from(loaded.asset_value.asset)
      end

    struct!(BoundValue, %{
      task_input_id: input.id,
      revision_id: revision.id,
      requirement_id: requirement.id,
      field_definition_id: binding.field_definition_id,
      binding_id: binding.id,
      missing: is_nil(value),
      value: value,
      asset: asset
    })
  end

  defp source_download(args, actor) do
    with {:ok, {asset, expiry}} <-
           QuickTrain.Repo.transaction(fn -> source_asset!(args, actor) end),
         {:ok, descriptor} <-
           Storage.sealed_read_access(asset.sealed_key, expiry) do
      {:ok, AssetAccessResult.from(asset, descriptor)}
    else
      {:error, error} when is_atom(error) ->
        {:error, QuickTrain.Tasks.Error.exception(category: error)}

      other ->
        other
    end
  end

  defp source_asset!(args, actor) do
    {project, input, deadline} = authorize_input!(args, actor)
    bound = bound_value!(project, input, args.requirement_id)
    if bound.missing, do: Error.reject!(:invalid_source)
    value = Ash.load!(bound.value, [asset_value: :asset], authorize?: false)
    asset = value.asset_value && value.asset_value.asset
    unless asset && asset.state == :ready, do: Error.reject!(:invalid_source)
    expiry = DateTime.add(Leases.now!(), 300, :second)
    expiry = if deadline && DateTime.compare(deadline, expiry) == :lt, do: deadline, else: expiry
    {asset, expiry}
  end
end
