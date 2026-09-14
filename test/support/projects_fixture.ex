defmodule QuickTrain.ProjectsFixture do
  @moduledoc false
  alias QuickTrain.{Datasets, Forms, FormsFixture, Projects}
  alias QuickTrain.Projects.ProjectItem
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

    Projects.enroll_revisions!(
      context.org.id,
      project.id,
      %{revision_ids: Enum.map(source.revisions, & &1.id)},
      actor: context.actor
    )

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

    Projects.set_question_policy!(
      context.org.id,
      project.id,
      %{
        question_id: source.form.question.id,
        accepted_target: 1,
        skip_allowed: true,
        reason_required: true,
        failure_threshold: 3
      },
      actor: context.actor
    )

    project
  end

  def active!(context, source, opts \\ []) do
    project = configured!(context, source, opts)
    Projects.activate_project!(context.org.id, project.id, actor: context.actor)
  end

  def items(project) do
    ProjectItem
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!(authorize?: false, page: false)
  end
end
