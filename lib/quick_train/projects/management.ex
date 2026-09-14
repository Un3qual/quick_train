defmodule QuickTrain.Projects.Management do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Authorization

  alias QuickTrain.Projects.{
    Error,
    ExplicitGroup,
    ExplicitGroupInput,
    GroupIdentity,
    Project,
    ProjectActivation,
    ProjectInputBinding,
    ProjectItem,
    ProjectQuestionPolicy,
    ProjectSlotPolicy,
    ProjectWorkerAccess
  }

  alias QuickTrain.Datasets.{DatasetItemRevision, DatasetSchemaVersion}
  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Tasks.{Leases, ProjectCompletion}
  require Ash.Query

  @configuration [
    :title,
    :audience,
    :external_access,
    :selection_mode,
    :review_mode,
    :coverage_target,
    :lease_minutes
  ]
  @source_states %{
    activate: [:draft],
    pause: [:active],
    resume: [:paused],
    complete: [:active, :paused],
    archive: [:completed]
  }
  @targets %{
    activate: :active,
    pause: :paused,
    resume: :active,
    complete: :completed,
    archive: :archived
  }

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
      Project
      |> Ash.Query.for_read(:lock, %{organization_id: organization_id, project_id: project_id},
        authorize?: false
      )
      |> Ash.read_one!()

    if is_nil(project), do: Error.reject!(:invalid_project)
    project
  end

  defp execute(%{action: %{name: :create_project}, arguments: args}, actor) do
    authorize!(actor, args.organization_id)
    authorize!(actor, args.organization_id, "datasets.read")
    authorize!(actor, args.organization_id, "forms.read")

    schema =
      DatasetSchemaVersion
      |> Ash.Query.filter(
        id == ^args.schema_version_id and dataset_id == ^args.dataset_id and
          dataset.organization_id == ^args.organization_id and state == :published
      )
      |> Ash.read_one!(authorize?: false)

    form_version =
      FormVersion
      |> Ash.Query.filter(
        id == ^args.form_version_id and form.organization_id == ^args.organization_id and
          state == :published
      )
      |> Ash.read_one!(authorize?: false)

    if is_nil(schema) or is_nil(form_version), do: Error.reject!(:invalid_project_configuration)

    attrs =
      args
      |> Map.take(
        @configuration ++ [:organization_id, :dataset_id, :schema_version_id, :form_version_id]
      )
      |> Map.merge(%{
        form_id: form_version.form_id,
        root_record_type_id: schema.root_record_type_id
      })

    create!(Project, attrs)
  end

  defp execute(input, actor) do
    args = input.arguments
    project = lock!(args.organization_id, args.project_id)
    authorize!(actor, project.organization_id)
    action = input.action.name

    cond do
      Map.has_key?(@targets, action) ->
        transition!(project, action)

      action == :update_title ->
        update!(project, %{title: args.title})

      action in [:set_worker_access, :remove_worker_access] ->
        edit!(project, action, args)

      project.state != :draft ->
        Error.reject!(:project_not_draft)

      true ->
        authorize_edit!(project, action, args, actor)
        edit!(project, action, args)
    end
  end

  defp transition!(project, action) do
    target = Map.fetch!(@targets, action)

    if project.state == target do
      project
    else
      unless project.state in Map.fetch!(@source_states, action),
        do: Error.reject!(:invalid_project_transition)

      if action == :activate, do: ProjectActivation.validate!(project)
      attrs = Map.put(transition_attributes!(project, action), :state, target)

      update!(project, attrs)
    end
  end

  defp authorize_edit!(project, :update_draft, args, actor) do
    if args[:dataset_id] || args[:schema_version_id],
      do: authorize!(actor, project.organization_id, "datasets.read")

    if args[:form_version_id], do: authorize!(actor, project.organization_id, "forms.read")
  end

  defp authorize_edit!(project, action, _args, actor) do
    if action in [:enroll_revisions, :set_binding],
      do: authorize!(actor, project.organization_id, "datasets.read")

    if action in [:set_binding, :set_slot_policy, :set_question_policy, :create_explicit_group],
      do: authorize!(actor, project.organization_id, "forms.read")
  end

  defp transition_attributes!(_project, :activate), do: %{activated_at: DateTime.utc_now()}
  defp transition_attributes!(_project, :archive), do: %{archived_at: DateTime.utc_now()}

  defp transition_attributes!(project, :complete) do
    cutoff = Leases.now!()
    ProjectCompletion.complete!(project, cutoff)
    %{completed_at: cutoff}
  end

  defp transition_attributes!(_project, _action), do: %{}

  defp schema_attributes!(project, args) do
    if args[:dataset_id] || args[:schema_version_id] do
      dataset_id = args[:dataset_id] || project.dataset_id
      schema_id = args[:schema_version_id] || project.schema_version_id

      schema =
        DatasetSchemaVersion
        |> Ash.Query.filter(
          id == ^schema_id and dataset_id == ^dataset_id and
            dataset.organization_id == ^project.organization_id and state == :published
        )
        |> Ash.read_one!(authorize?: false)

      if is_nil(schema), do: Error.reject!(:invalid_project_configuration)

      %{
        dataset_id: dataset_id,
        schema_version_id: schema_id,
        root_record_type_id: schema.root_record_type_id
      }
    else
      %{}
    end
  end

  defp form_attributes!(project, args) do
    if args[:form_version_id] do
      version =
        FormVersion
        |> Ash.Query.filter(
          id == ^args.form_version_id and form.organization_id == ^project.organization_id and
            state == :published
        )
        |> Ash.read_one!(authorize?: false)

      if is_nil(version), do: Error.reject!(:invalid_project_configuration)
      %{form_id: version.form_id, form_version_id: version.id}
    else
      %{}
    end
  end

  defp edit!(project, :update_draft, args) do
    attrs = args |> Map.take(@configuration) |> Map.reject(fn {_key, value} -> is_nil(value) end)

    attrs =
      attrs
      |> Map.merge(schema_attributes!(project, args))
      |> Map.merge(form_attributes!(project, args))

    update!(project, attrs)
  end

  defp edit!(project, action, args)
       when action in [:remove_binding, :remove_slot_policy, :remove_question_policy] do
    {resource, key} =
      case action do
        :remove_binding -> {ProjectInputBinding, :requirement_id}
        :remove_slot_policy -> {ProjectSlotPolicy, :input_slot_id}
        :remove_question_policy -> {ProjectQuestionPolicy, :question_id}
      end

    filter = [project_id: project.id] ++ [{key, Map.fetch!(args, key)}]
    row = resource |> Ash.Query.filter(^filter) |> Ash.read_one!(authorize?: false)
    if is_nil(row), do: Error.reject!(:invalid_project_configuration)
    Ash.destroy!(row, action: :destroy_internal, authorize?: false)
    project
  end

  defp edit!(project, :enroll_revisions, args) do
    if args.revision_ids == [] or Enum.uniq(args.revision_ids) != args.revision_ids,
      do: Error.reject!(:invalid_project_configuration)

    for id <- args.revision_ids do
      revision =
        DatasetItemRevision
        |> Ash.Query.filter(
          id == ^id and organization_id == ^project.organization_id and
            dataset_id == ^project.dataset_id and schema_version_id == ^project.schema_version_id
        )
        |> Ash.read_one!(authorize?: false)

      if is_nil(revision), do: Error.reject!(:invalid_project_configuration)

      create!(ProjectItem, %{
        project_id: project.id,
        dataset_id: project.dataset_id,
        schema_version_id: project.schema_version_id,
        item_id: revision.item_id,
        revision_id: revision.id
      })
    end

    project
  end

  defp edit!(project, :remove_project_items, args) do
    if args.project_item_ids == [], do: Error.reject!(:invalid_project_configuration)

    for id <- Enum.uniq(args.project_item_ids) do
      row = scoped!(ProjectItem, project, id)
      Ash.destroy!(row, action: :destroy_internal, authorize?: false)
    end

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

  defp edit!(project, :set_question_policy, args) do
    ProjectActivation.definition!(
      QuickTrain.Forms.Questions.QuestionDefinition,
      project,
      args.question_id
    )

    put!(
      ProjectQuestionPolicy,
      project,
      [question_id: args.question_id],
      args
      |> Map.take([:accepted_target, :skip_allowed, :reason_required, :failure_threshold])
      |> Map.put(:form_version_id, project.form_version_id)
    )

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
    if project.selection_mode != :explicit, do: Error.reject!(:invalid_project_configuration)
    ProjectActivation.validate_group!(project, args.inputs)
    {key, _encoding} = GroupIdentity.canonical(args.inputs)

    group =
      create!(ExplicitGroup, %{
        project_id: project.id,
        form_version_id: project.form_version_id,
        position: args.position,
        canonical_key: key
      })

    for input <- args.inputs do
      create!(
        ExplicitGroupInput,
        input
        |> Map.take([:project_item_id, :input_slot_id, :position])
        |> Map.merge(%{
          project_id: project.id,
          group_id: group.id,
          form_version_id: project.form_version_id
        })
      )
    end

    project
  end

  defp edit!(project, :remove_explicit_group, args) do
    group = scoped!(ExplicitGroup, project, args.group_id)

    ProjectActivation.rows(ExplicitGroupInput, project_id: project.id, group_id: group.id)
    |> Enum.each(&Ash.destroy!(&1, action: :destroy_internal, authorize?: false))

    Ash.destroy!(group, action: :destroy_internal, authorize?: false)
    project
  end

  defp put!(resource, project, identity, attrs) do
    filter = Keyword.put(identity, :project_id, project.id)
    existing = resource |> Ash.Query.filter(^filter) |> Ash.read_one!(authorize?: false)

    if existing do
      accepted = Ash.Resource.Info.action(resource, :update_internal).accept
      update!(existing, Map.take(attrs, accepted))
    else
      create!(resource, Map.merge(Map.new(filter), attrs))
    end
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

  defp update!(record, attrs),
    do: Ash.update!(record, attrs, action: :update_internal, authorize?: false)
end
