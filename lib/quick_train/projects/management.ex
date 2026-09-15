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
    ProjectItem
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

    if project.state != :draft,
      do: Error.reject!(:project_not_draft)

    authorize_edit!(project, action, actor)
    edit!(project, action, args)
  end

  defp authorize_edit!(project, action, actor) do
    if action == :enroll_revisions,
      do: authorize!(actor, project.organization_id, "datasets.read")

    if action == :create_explicit_group,
      do: authorize!(actor, project.organization_id, "forms.read")
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

  defp edit!(project, :create_explicit_group, args) do
    ProjectActivation.validate_group!(project, args.inputs)
    key = GroupIdentity.key(args.inputs)

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
