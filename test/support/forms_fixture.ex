defmodule QuickTrain.FormsFixture do
  @moduledoc false
  alias QuickTrain.{Accounts, Authorization, Forms, Organizations}

  alias QuickTrain.Forms.FormVersion
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.IntegerConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition

  def context!(capabilities \\ ~w(forms.read forms.manage), suffix \\ "forms") do
    actor = Accounts.register_user!("#{suffix}@example.test", "Form Author")
    org = Organizations.create_organization!("Forms", suffix)
    membership = Organizations.add_member!(org.id, actor.id)
    role = Authorization.create_role!(org.id, "author", "Author")
    Authorization.assign_role!(org.id, actor.id, role.id)

    for key <- capabilities do
      capability =
        Authorization.create_capability!(key, key,
          upsert?: true,
          upsert_identity: :key,
          upsert_fields: []
        )

      Authorization.grant_capability!(role.id, capability.id)
    end

    %{actor: actor, org: org, membership: membership}
  end

  def draft!(context, key \\ "form") do
    form = Forms.create_form!(context.org.id, %{key: key}, actor: context.actor)

    version =
      Forms.create_form_draft!(context.org.id, %{form_id: form.id, title: "Form"},
        actor: context.actor
      )

    %{form: form, version: version}
  end

  def rating!(context) do
    %{form: form, version: version} = draft!(context)
    slot = add!(InputSlotDefinition, context, version, %{key: "item", minimum: 1, maximum: 1})

    field =
      add!(InputFieldRequirement, context, version, %{
        input_slot_id: slot.id,
        key: "body",
        value_family: :text,
        required: true
      })

    question =
      add!(QuestionDefinition, context, version, %{
        key: "rating",
        prompt: "Rate it",
        family: :integer,
        renderer: :stars
      })

    bounds =
      add!(IntegerConstraints, context, version, %{
        question_id: question.id,
        minimum: 1,
        maximum: 5
      })

    element =
      add!(PresentationElement, context, version, %{
        kind: :question,
        position: 10,
        question_id: question.id
      })

    %{
      form: form,
      version: version,
      slot: slot,
      field: field,
      question: question,
      bounds: bounds,
      element: element
    }
  end

  def add!(resource, context, version, attrs),
    do: run!(resource, :add_to_draft, context, Map.put(attrs, :version_id, version.id))

  def edit(resource, context, record, attrs),
    do:
      run(
        resource,
        :update_in_draft,
        context,
        Map.merge(attrs, %{version_id: record.version_id, id: record.id})
      )

  # Parameterized contract tests exercise the same generated domain functions as callers.
  def run!(resource, action, context, attrs), do: invoke(resource, action, context, attrs, "!")
  def run(resource, action, context, attrs), do: invoke(resource, action, context, attrs, "")

  defp invoke(resource, action, context, attrs, suffix) do
    reference = Enum.find(Ash.Domain.Info.resource_references(Forms), &(&1.resource == resource))
    interface = Enum.find(reference.definitions, &(&1.action == action))
    attrs = Map.put(attrs, :organization_id, context.org.id)

    attrs =
      if resource == FormVersion and action == :update_draft,
        do: attrs |> Map.put(:id, attrs.version_id) |> Map.delete(:version_id),
        else: attrs

    action_type = Ash.Resource.Info.action(resource, action).type

    record_args =
      if action_type in [:update, :destroy],
        do: [Ash.get!(resource, attrs.id, authorize?: false)],
        else: []

    inputs =
      record_args ++
        Enum.map(interface.args, &Map.fetch!(attrs, &1)) ++
        [Map.drop(attrs, [:id | interface.args]), [actor: context.actor]]

    apply(Forms, String.to_existing_atom("#{interface.name}#{suffix}"), inputs)
  end
end
