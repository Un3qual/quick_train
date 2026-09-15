defmodule QuickTrain.Tasks.Access.ReadActions do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Assets.{AssetAccessResult, AssetSummary, Storage}
  alias QuickTrain.Datasets.{DatasetItemRevision, DatasetValue}
  alias QuickTrain.Projects.ProjectInputBinding
  alias QuickTrain.Tasks.{Access, Error, TaskInput}
  alias QuickTrain.Tasks.Access.BoundValue
  alias QuickTrain.Tasks.Attempts.{Attempt, Leases, Receipt}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.QuestionReview
  require Ash.Query

  def run(%{action: %{name: :work_bundle}, arguments: args}, _opts, context) do
    QuickTrain.Tasks.work_bundle(args.organization_id, args.project_id, args.attempt_id,
      scope: context
    )
  end

  def run(input, _opts, context) do
    if is_nil(context.actor), do: Error.reject!(:forbidden)

    if input.action.name == :source_download do
      source_download(input.arguments, context.actor)
    else
      {:ok, execute(input, context.actor)}
    end
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown, Postgrex.Error] ->
      {:error, error}
  end

  defp execute(%{action: %{name: :receipt}, arguments: args}, actor) do
    project = Access.project!(args.organization_id, args.project_id)

    attempt =
      Attempt
      |> Ash.Query.filter(id == ^args.attempt_id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)
      |> Access.found!()

    Access.owner!(project, attempt, actor, false)

    if attempt.state in Leases.live_states(), do: Error.reject!(:attempt_not_terminal)

    counts =
      if attempt.state == :submitted do
        QuestionResponse
        |> Ash.Query.filter(attempt_id == ^attempt.id)
        |> Ash.Query.load(:effective_decision)
        |> Ash.stream!(authorize?: false)
        |> Enum.frequencies_by(&QuestionReview.effective_status/1)
      else
        %{}
      end

    struct!(
      Receipt,
      Map.merge(Map.take(attempt, [:id, :state, :started_at, :terminal_at, :inserted_at]), counts)
    )
  end

  defp execute(%{action: %{name: :bound_value}, arguments: args}, actor) do
    {project, input, _deadline} = authorize_input!(args, actor)
    {bound, _asset} = resolve_bound_value!(project, input, args.requirement_id)
    bound
  end

  defp authorize_input!(args, actor) do
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

  defp resolve_bound_value!(project, input, requirement_id) do
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
        if loaded.asset_value, do: loaded.asset_value.asset
      end

    bound =
      struct!(BoundValue, %{
        task_input_id: input.id,
        revision_id: revision.id,
        requirement_id: binding.requirement_id,
        field_definition_id: binding.field_definition_id,
        binding_id: binding.id,
        missing: is_nil(value),
        value: value,
        asset: if(asset, do: AssetSummary.from(asset))
      })

    {bound, asset}
  end

  defp source_download(args, actor) do
    with {:ok, {asset, expiry}} <-
           Ash.transact(Attempt, fn -> source_asset!(args, actor) end),
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
    {_bound, asset} = resolve_bound_value!(project, input, args.requirement_id)
    unless asset && asset.state == :ready, do: Error.reject!(:invalid_source)
    expiry = DateTime.add(Leases.now!(), 300, :second)
    expiry = if deadline && DateTime.compare(deadline, expiry) == :lt, do: deadline, else: expiry
    {asset, expiry}
  end
end
