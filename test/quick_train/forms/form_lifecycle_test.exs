defmodule QuickTrain.Forms.FormLifecycleTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.Accounts

  alias QuickTrain.Forms.{Form, FormVersion}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Presentation.PresentationElement
  alias QuickTrain.Forms.Questions.Constraints.IntegerConstraints
  alias QuickTrain.Forms.Questions.QuestionDefinition

  setup do
    actor = Accounts.register_user!("forms@example.test", "Forms Author")
    %{organization: org} = organization_manager_fixture(actor.id, "forms", "Forms")
    %{actor: actor, org: org}
  end

  test "an organization can publish a reusable rating contract and copy it", context do
    form = run!(Form, :create_form, context, %{key: "rating"})

    version =
      run!(FormVersion, :create_draft, context, %{form_id: form.id, title: "Rate this item"})

    slot = add!(InputSlotDefinition, context, version, %{key: "item", minimum: 1, maximum: 1})

    add!(InputFieldRequirement, context, version, %{
      input_slot_id: slot.id,
      key: "body",
      value_family: :text,
      cardinality: :single,
      required: true
    })

    question =
      add!(QuestionDefinition, context, version, %{
        key: "rating",
        prompt: "How good?",
        family: :integer,
        renderer: :stars
      })

    add!(IntegerConstraints, context, version, %{question_id: question.id, minimum: 1, maximum: 5})

    element =
      add!(PresentationElement, context, version, %{
        kind: :question,
        position: 0,
        question_id: question.id
      })

    published = run!(FormVersion, :publish, context, %{version_id: version.id})
    assert published.state == :published
    assert %DateTime{} = published.published_at

    assert run!(FormVersion, :publish, context, %{version_id: version.id}).published_at ==
             published.published_at

    assert {:error, _} =
             run(FormVersion, :update_draft, context, %{version_id: version.id, title: "Changed"})

    assert {:error, _} =
             run(PresentationElement, :remove_from_draft, context, %{
               version_id: version.id,
               id: element.id
             })

    copied =
      run!(FormVersion, :copy_published, context, %{
        form_id: form.id,
        source_version_id: version.id
      })

    assert copied.version == 2
    assert copied.state == :draft
    assert copied.title == published.title
    assert run!(FormVersion, :publish, context, %{version_id: copied.id}).state == :published
    next = run!(FormVersion, :create_draft, context, %{form_id: form.id})
    assert next.version == 3
  end

  test "publication failure preserves a repairable draft", context do
    form = run!(Form, :create_form, context, %{key: "incomplete"})
    version = run!(FormVersion, :create_draft, context, %{form_id: form.id, title: " "})
    assert {:error, _} = run(FormVersion, :publish, context, %{version_id: version.id})
    assert Ash.get!(FormVersion, version.id, authorize?: false).state == :draft

    assert run!(FormVersion, :update_draft, context, %{version_id: version.id, title: "Repaired"}).title ==
             "Repaired"
  end

  defp add!(resource, context, version, attrs),
    do: run!(resource, :add_to_draft, context, Map.put(attrs, :version_id, version.id))

  defp run!(resource, action, context, attrs) do
    case run(resource, action, context, attrs) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp run(resource, action, context, attrs) do
    resource
    |> Ash.ActionInput.for_action(action, Map.put(attrs, :organization_id, context.org.id),
      actor: context.actor
    )
    |> Ash.run_action()
  end
end
