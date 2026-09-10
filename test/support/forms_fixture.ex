defmodule QuickTrain.FormsFixture do
  @moduledoc false
  alias QuickTrain.{Accounts, Authorization, Organizations}

  alias QuickTrain.Forms.{Form, FormVersion}
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
    form = run!(Form, :create_form, context, %{key: key})
    version = run!(FormVersion, :create_draft, context, %{form_id: form.id, title: "Form"})
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

  def run!(resource, action, context, attrs) do
    case run(resource, action, context, attrs) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def run(resource, action, context, attrs) do
    resource
    |> Ash.ActionInput.for_action(action, Map.put(attrs, :organization_id, context.org.id),
      actor: context.actor
    )
    |> Ash.run_action()
  end
end
