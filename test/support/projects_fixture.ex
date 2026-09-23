defmodule QuickTrain.ProjectsFixture do
  @moduledoc false
  alias QuickTrain.{Datasets, Forms, FormsFixture, Projects, Tasks}
  alias QuickTrain.Tasks.TaskInput
  require Ash.Query

  def context!(
        capabilities \\ ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage),
        suffix \\ "projects"
      ) do
    FormsFixture.context!(capabilities, suffix)
  end

  def source!(context, opts \\ []) do
    form = FormsFixture.rating!(context)

    form =
      if maximum = opts[:slot_maximum] do
        {:ok, slot} =
          FormsFixture.edit(QuickTrain.Forms.Inputs.InputSlotDefinition, context, form.slot, %{
            maximum: maximum
          })

        %{form | slot: slot}
      else
        form
      end

    form =
      if opts[:image_requirement] do
        FormsFixture.add!(QuickTrain.Forms.Inputs.InputFieldRequirement, context, form.version, %{
          input_slot_id: form.slot.id,
          key: "image",
          value_family: :asset,
          required: false,
          intended_use: :image
        })

        form
      else
        form
      end

    extra_requirements =
      for index <- 1..Keyword.get(opts, :extra_bound_fields, 0)//1 do
        FormsFixture.add!(QuickTrain.Forms.Inputs.InputFieldRequirement, context, form.version, %{
          input_slot_id: form.slot.id,
          key: "extra_#{index}",
          value_family: :text,
          required: false
        })
      end

    version =
      Forms.publish_form_version!(form.version, context.org.id, %{}, actor: context.actor)

    dataset = Datasets.create_dataset!(context.org.id, "items", "Items", actor: context.actor)
    schema = Datasets.create_schema_version!(context.org.id, dataset.id, actor: context.actor)

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "item", "Item", actor: context.actor)

    field =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "body",
        "Body",
        "text",
        "single",
        true,
        actor: context.actor
      )

    extra_bindings =
      for requirement <- extra_requirements do
        field =
          Datasets.add_field_definition!(
            context.org.id,
            root.id,
            requirement.key,
            requirement.key,
            "text",
            "single",
            false,
            actor: context.actor
          )

        {requirement, field}
      end

    schema =
      Datasets.publish_schema_version!(schema, context.org.id, root.id, actor: context.actor)

    revisions =
      for number <- 1..Keyword.get(opts, :item_count, 2)//1 do
        Datasets.put_item_revision!(
          context.org.id,
          dataset.id,
          schema.id,
          nil,
          "item-#{number}",
          [%{field: "body", text: "Body #{number}"}] ++
            Enum.map(extra_requirements, &%{field: &1.key, text: "#{&1.key} for item #{number}"}),
          actor: context.actor
        ).revision
      end

    %{
      form: %{form | version: version},
      dataset: dataset,
      schema: schema,
      root: root,
      field: field,
      revisions: revisions,
      extra_bindings: extra_bindings
    }
  end

  def draft!(context, source, opts \\ []) do
    Projects.create_project!(
      context.org.id,
      Map.merge(
        %{
          title: "Collection",
          dataset_id: source.dataset.id,
          schema_version_id: source.schema.id,
          form_version_id: source.form.version.id,
          skip_allowed: true,
          reason_required: true
        },
        Map.new(opts)
      ),
      actor: context.actor
    )
  end

  def configured!(context, source, opts \\ []) do
    {tasks?, opts} = Keyword.pop(opts, :tasks, true)
    project = draft!(context, source, opts)

    Projects.set_binding!(
      context.org.id,
      project.id,
      %{
        requirement_id: source.form.field.id,
        field_definition_id: source.field.id
      },
      actor: context.actor
    )

    Projects.set_slot_policy!(
      context.org.id,
      project.id,
      %{
        input_slot_id: source.form.slot.id,
        item_count: 1,
        shuffle: false
      },
      actor: context.actor
    )

    if tasks?, do: tasks!(context, source, project)

    project
  end

  def active!(context, source, opts \\ []) do
    project = configured!(context, source, opts)
    Projects.activate_project!(project, actor: context.actor)
  end

  def tasks!(context, source, project) do
    for {item, position} <- Enum.with_index(source.revisions) do
      Tasks.create_task!(
        context.org.id,
        project.id,
        %{
          position: position,
          inputs: [%{input_slot_id: source.form.slot.id, revision_id: item.id, position: 0}]
        },
        actor: context.actor
      )
    end
  end

  def inputs(project) do
    TaskInput
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!(authorize?: false, page: false)
  end
end
