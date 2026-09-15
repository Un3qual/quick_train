defmodule QuickTrain.Projects.Management do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.{Authorization, Projects}

  alias QuickTrain.Projects.{
    Error,
    ExplicitGroup,
    ExplicitGroupInput,
    GroupIdentity,
    ProjectActivation,
    ProjectInputBinding,
    ProjectItem,
    ProjectSlotPolicy,
    ProjectWorkerAccess
  }

  alias QuickTrain.Datasets.DatasetItemRevision
  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    {:ok, execute(input, context.actor)}
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown, Postgrex.Error] ->
      {:error, error}
  end

  def authorize!(actor, organization_id, capability \\ "projects.manage") do
    unless match?(%{status: "active"}, actor) and
             Authorization.allowed?(actor.id, organization_id, capability),
           do: raise(Ash.Error.Forbidden)
  end

  def lock!(organization_id, project_id) do
    project =
      Projects.lock_project!(organization_id, project_id, authorize?: false)

    if is_nil(project), do: Error.reject!(:invalid_project)
    project
  end

  defp execute(input, actor) do
    args = input.arguments
    project = lock!(args.organization_id, args.project_id)
    authorize!(actor, project.organization_id)
    action = input.action.name

    if project.state != :draft and action not in [:set_worker_access, :remove_worker_access],
      do: Error.reject!(:project_not_draft)

    authorize_edit!(project, action, args, actor)
    edit!(project, action, args)
  end

  defp authorize_edit!(project, action, _args, actor) do
    if action in [:enroll_revisions, :set_binding],
      do: authorize!(actor, project.organization_id, "datasets.read")

    if action in [:set_binding, :set_slot_policy, :create_explicit_group],
      do: authorize!(actor, project.organization_id, "forms.read")
  end

  defp edit!(project, action, args)
       when action in [:remove_binding, :remove_slot_policy] do
    {resource, key} =
      case action do
        :remove_binding -> {ProjectInputBinding, :requirement_id}
        :remove_slot_policy -> {ProjectSlotPolicy, :input_slot_id}
      end

    filter = [project_id: project.id] ++ [{key, Map.fetch!(args, key)}]
    row = resource |> Ash.Query.filter(^filter) |> Ash.read_one!(authorize?: false)
    if is_nil(row), do: Error.reject!(:invalid_project_configuration)
    Ash.destroy!(row, action: :destroy_internal, authorize?: false)
    project
  end

  defp edit!(project, :enroll_revisions, args) do
    if Enum.uniq(args.revision_ids) != args.revision_ids,
      do: Error.reject!(:invalid_project_configuration)

    revisions =
      DatasetItemRevision
      |> Ash.Query.filter(
        id in ^args.revision_ids and organization_id == ^project.organization_id and
          dataset_id == ^project.dataset_id and schema_version_id == ^project.schema_version_id
      )
      |> Ash.read!(authorize?: false, page: false)

    if length(revisions) != length(args.revision_ids),
      do: Error.reject!(:invalid_project_configuration)

    revisions
    |> Enum.map(fn revision ->
      %{
        project_id: project.id,
        dataset_id: project.dataset_id,
        schema_version_id: project.schema_version_id,
        item_id: revision.item_id,
        revision_id: revision.id
      }
    end)
    |> Ash.bulk_create!(ProjectItem, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )

    project
  end

  defp edit!(project, :remove_project_items, args) do
    ids = Enum.uniq(args.project_item_ids)
    query = Ash.Query.filter(ProjectItem, project_id == ^project.id and id in ^ids)

    if Ash.count!(query, authorize?: false) != length(ids),
      do: Error.reject!(:invalid_project_configuration)

    Ash.bulk_destroy!(query, :destroy_internal, %{},
      strategy: [:atomic],
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )

    project
  end

  defp edit!(project, :set_binding, args) do
    ProjectActivation.validate_binding!(project, args.requirement_id, args.field_definition_id)

    put!(ProjectInputBinding, project, [requirement_id: args.requirement_id], %{
      schema_version_id: project.schema_version_id,
      root_record_type_id: project.root_record_type_id,
      form_version_id: project.form_version_id,
      field_definition_id: args.field_definition_id
    })

    project
  end

  defp edit!(project, :set_slot_policy, args) do
    ProjectActivation.validate_slot!(project, args.input_slot_id, args.item_count)

    put!(ProjectSlotPolicy, project, [input_slot_id: args.input_slot_id], %{
      form_version_id: project.form_version_id,
      item_count: args.item_count,
      shuffle: args.shuffle
    })

    project
  end

  defp edit!(project, :set_worker_access, args) do
    unless Ash.exists?(QuickTrain.Accounts.User,
             query: [filter: [id: args.user_id]],
             authorize?: false
           ),
           do: Error.reject!(:invalid_project_configuration)

    put!(ProjectWorkerAccess, project, [user_id: args.user_id], %{disposition: args.disposition})
    project
  end

  defp edit!(project, :remove_worker_access, args) do
    row =
      ProjectWorkerAccess
      |> Ash.Query.filter(project_id == ^project.id and user_id == ^args.user_id)
      |> Ash.read_one!(authorize?: false)

    if row, do: Ash.destroy!(row, action: :destroy_internal, authorize?: false)
    project
  end

  defp edit!(project, :create_explicit_group, args) do
    ProjectActivation.validate_group!(project, args.inputs)
    {key, _encoding} = GroupIdentity.canonical(args.inputs)

    group =
      create!(ExplicitGroup, %{
        project_id: project.id,
        form_version_id: project.form_version_id,
        position: args.position,
        canonical_key: key
      })

    args.inputs
    |> Enum.map(fn input ->
      input
      |> Map.take([:project_item_id, :input_slot_id, :position])
      |> Map.merge(%{
        project_id: project.id,
        group_id: group.id,
        form_version_id: project.form_version_id
      })
    end)
    |> Ash.bulk_create!(ExplicitGroupInput, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )

    project
  end

  defp edit!(project, :remove_explicit_group, args) do
    group = scoped!(ExplicitGroup, project, args.group_id)

    Ash.destroy!(group, action: :destroy_internal, authorize?: false)
    project
  end

  defp put!(resource, project, identity, attrs) do
    create!(resource, Map.merge(attrs, Map.new([{:project_id, project.id} | identity])))
  end

  defp scoped!(resource, project, id) do
    row =
      resource
      |> Ash.Query.filter(id == ^id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)

    if is_nil(row), do: Error.reject!(:invalid_project_configuration)
    row
  end

  defp create!(resource, attrs),
    do: Ash.create!(resource, attrs, action: :create_internal, authorize?: false)
end
