defmodule QuickTrain.ProjectsFixture do
  @moduledoc false
  alias QuickTrain.{Datasets, Forms, FormsFixture, Projects}
  alias QuickTrain.Projects.{Project, ProjectItem}
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

    version =
      Forms.publish_form_version!(context.org.id, %{version_id: form.version.id},
        actor: context.actor
      )

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

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    revisions =
      for number <- 1..Keyword.get(opts, :item_count, 2) do
        Datasets.put_item_revision!(
          context.org.id,
          dataset.id,
          schema.id,
          nil,
          "item-#{number}",
          [%{field: "body", text: "Body #{number}"}],
          actor: context.actor
        ).revision
      end

    %{
      form: %{form | version: version},
      dataset: dataset,
      schema: schema,
      root: root,
      field: field,
      revisions: revisions
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
          form_version_id: source.form.version.id
        },
        Map.new(opts)
      ),
      actor: context.actor
    )
  end

  def configured!(context, source, opts \\ []) do
    project = draft!(context, source, opts)

    run!(context, project, :enroll_revisions, %{revision_ids: Enum.map(source.revisions, & &1.id)})

    run!(context, project, :set_binding, %{
      requirement_id: source.form.field.id,
      field_definition_id: source.field.id
    })

    run!(context, project, :set_slot_policy, %{
      input_slot_id: source.form.slot.id,
      item_count: 1,
      shuffle: false
    })

    run!(context, project, :set_question_policy, %{
      question_id: source.form.question.id,
      accepted_target: 1,
      skip_allowed: true,
      reason_required: true,
      failure_threshold: 3
    })

    project
  end

  def active!(context, source, opts \\ []) do
    project = configured!(context, source, opts)
    run!(context, project, :activate)
  end

  def items(project) do
    ProjectItem
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!(authorize?: false, page: false)
  end

  def run(context, project, action, attrs \\ %{}) do
    Project
    |> Ash.ActionInput.for_action(
      action,
      Map.merge(attrs, %{organization_id: context.org.id, project_id: project.id}),
      actor: context.actor
    )
    |> Ash.run_action()
  end

  def run!(context, project, action, attrs \\ %{}) do
    Project
    |> Ash.ActionInput.for_action(
      action,
      Map.merge(attrs, %{organization_id: context.org.id, project_id: project.id}),
      actor: context.actor
    )
    |> Ash.run_action!()
  end
end
