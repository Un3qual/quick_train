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
    TextSpan,
    TaskQuestionProgress,
    TaskItemCoverage
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
    live = live_attempt(actor)

    worker =
      case resource do
        Task ->
          expr(exists(Attempt, task_id == parent(id) and ^live))

        TaskInput ->
          expr(exists(Attempt, task_id == parent(task_id) and ^live))

        Attempt ->
          live

        module when module in [AttemptQuestion, AttemptInputPresentation, Response] ->
          expr(exists(attempt, ^live))

        QuestionResponse ->
          expr(exists(response.attempt, ^live))

        module when module in [StaticOptionAnswer, TaskInputAnswer, TextSpan] ->
          expr(exists(question_response.response.attempt, ^live))

        module when module in [ReviewDecision, TaskQuestionProgress, TaskItemCoverage] ->
          false
      end

    worker =
      if receipt? and resource == AttemptQuestion do
        eligible = eligible_attempt(actor)
        expr(exists(attempt, ^eligible))
      else
        worker
      end

    authority = result_authority(actor)
    evidence = evidence_filter(resource, mode)
    expr(^worker or (^authority and ^evidence))
  end

  def evidence_filter(resource, mode) do
    base =
      case resource do
        module when module in [Task, TaskInput, TaskQuestionProgress] ->
          true

        TaskItemCoverage ->
          expr(exists(issued_inputs, true))

        Attempt ->
          expr(state in [:submitted, :expired, :released, :cancelled])

        module when module in [AttemptQuestion, AttemptInputPresentation] ->
          expr(attempt.state in [:submitted, :expired, :released, :cancelled])

        Response ->
          expr(state == :submitted)

        QuestionResponse ->
          expr(response.state == :submitted)

        module when module in [StaticOptionAnswer, TaskInputAnswer, TextSpan, ReviewDecision] ->
          expr(question_response.response.state == :submitted)
      end

    accepted =
      case resource do
        Task ->
          expr(exists(outcomes, response.state == :submitted and effective_verdict == :accept))

        module when module in [TaskInput, TaskQuestionProgress] ->
          expr(
            exists(task.outcomes, response.state == :submitted and effective_verdict == :accept)
          )

        TaskItemCoverage ->
          expr(
            exists(
              issued_inputs.task.outcomes,
              response.state == :submitted and effective_verdict == :accept
            )
          )

        Attempt ->
          expr(exists(response.outcomes, effective_verdict == :accept))

        AttemptQuestion ->
          expr(
            exists(
              attempt.response.outcomes,
              effective_verdict == :accept
            )
          )

        AttemptInputPresentation ->
          expr(exists(attempt.response.outcomes, effective_verdict == :accept))

        Response ->
          expr(exists(outcomes, effective_verdict == :accept))

        QuestionResponse ->
          expr(effective_verdict == :accept)

        module when module in [StaticOptionAnswer, TaskInputAnswer, TextSpan] ->
          expr(question_response.effective_verdict == :accept)

        ReviewDecision ->
          expr(
            question_response.effective_verdict == :accept and
              number == question_response.effective_decision_number
          )
      end

    if mode == :accepted, do: expr(^base and ^accepted), else: base
  end
end

defmodule QuickTrain.Tasks.ReadAccess.Prepare do
  @moduledoc false
  use Ash.Resource.Preparation
  require Ash.Query

  def prepare(query, opts, _context) do
    mode = Keyword.fetch!(opts, :mode)
    filter = QuickTrain.Tasks.ReadAccess.evidence_filter(query.resource, mode)

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
  alias QuickTrain.Tasks.{Access, Attempt, BoundValue, Error, Leases, Receipt, TaskInput}
  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Datasets.DatasetValue
  alias QuickTrain.Forms.Inputs.InputFieldRequirement
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
      Ash.get!(QuickTrain.Datasets.DatasetItemRevision, input.revision_id, authorize?: false)

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
        if loaded.asset_value, do: QuickTrain.Assets.AssetSummary.from(loaded.asset_value.asset)
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
           QuickTrain.Repo.transaction(fn ->
             {project, input, deadline} = authorize_input!(args, actor)
             bound = bound_value!(project, input, args.requirement_id)
             if bound.missing, do: Error.reject!(:invalid_source)
             value = Ash.load!(bound.value, [asset_value: :asset], authorize?: false)
             asset = value.asset_value && value.asset_value.asset
             unless asset && asset.state == :ready, do: Error.reject!(:invalid_source)
             expiry = DateTime.add(Leases.now!(), 300, :second)

             expiry =
               if deadline && DateTime.compare(deadline, expiry) == :lt,
                 do: deadline,
                 else: expiry

             {asset, expiry}
           end),
         {:ok, descriptor} <-
           QuickTrain.Assets.Storage.sealed_read_access(asset.sealed_key, expiry) do
      {:ok, QuickTrain.Assets.AssetAccessResult.from(asset, descriptor)}
    else
      {:error, error} when is_atom(error) ->
        {:error, QuickTrain.Tasks.Error.exception(category: error)}

      other ->
        other
    end
  end
end
