defmodule QuickTrain.Forms.FormAuthorizationTest do
  use QuickTrain.DataCase, async: true
  import QuickTrain.FormsFixture
  alias QuickTrain.{Accounts, Authorization, Forms, Organizations}
  alias QuickTrain.Forms.{Form, FormVersion}
  alias QuickTrain.Forms.Questions.QuestionDefinition

  setup do
    ctx = context!()
    Map.merge(ctx, rating!(ctx))
  end

  test "unscoped reads and internal writes fail closed", ctx do
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(FormVersion, actor: ctx.actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(FormVersion, action: :read_for_authoring, actor: ctx.actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(Form, %{organization_id: ctx.org.id, key: "internal"},
               action: :create_internal,
               actor: ctx.actor
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(ctx.version, %{}, action: :publish_internal, actor: ctx.actor)
  end

  test "nested reads recheck account and organization capability", ctx do
    outsider = Accounts.register_user!("outsider@example.test", "Outsider")
    member = Accounts.register_user!("unprivileged@example.test", "Member")
    Organizations.add_member!(ctx.org.id, member.id)

    for actor <- [nil, outsider, member, %{ctx.actor | status: "disabled"}] do
      result = Ash.load(ctx.version, :questions, actor: actor)

      assert match?({:error, %Ash.Error.Forbidden{}}, result) or
               match?({:ok, %{questions: []}}, result)
    end
  end

  test "public actions reject inactive and unauthorized subjects without foreign disclosure",
       ctx do
    outsider = Accounts.register_user!("outsider@example.test", "Outsider")
    member = Accounts.register_user!("member@example.test", "Member")
    Organizations.add_member!(ctx.org.id, member.id)

    for actor <- [nil, outsider, member, %{ctx.actor | status: "disabled"}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               run(FormVersion, :publish, %{ctx | actor: actor}, %{version_id: ctx.version.id})

      assert {:error, %Ash.Error.Forbidden{}} =
               Forms.get_form_version(ctx.org.id, ctx.version.id, actor: actor)
    end

    other = context!(~w(forms.read forms.manage), "other")
    assert {:error, error} = run(FormVersion, :publish, other, %{version_id: ctx.version.id})
    assert Exception.message(error) =~ "invalid_form_version"
    refute Exception.message(error) =~ ctx.version.id

    assert {:error, _} =
             run(QuestionDefinition, :update_in_draft, other, %{
               version_id: ctx.version.id,
               id: ctx.question.id,
               prompt: "Foreign"
             })

    Organizations.deactivate_membership!(ctx.membership)

    assert {:error, %Ash.Error.Forbidden{}} =
             run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})

    Organizations.add_member!(ctx.org.id, ctx.actor.id)
    Ash.update!(ctx.org, %{status: "inactive"}, action: :update, authorize?: false)

    assert {:error, %Ash.Error.Forbidden{}} =
             run(FormVersion, :publish, ctx, %{version_id: ctx.version.id})
  end

  test "read-only members inspect but cannot author", ctx do
    reader = Accounts.register_user!("reader@example.test", "Reader")
    Organizations.add_member!(ctx.org.id, reader.id)
    role = Authorization.create_role!(ctx.org.id, "reader", "Reader")
    Authorization.assign_role!(ctx.org.id, reader.id, role.id)

    capability =
      Authorization.create_capability!("forms.read", "Read",
        upsert?: true,
        upsert_identity: :key,
        upsert_fields: []
      )

    Authorization.grant_capability!(role.id, capability.id)

    assert {:ok, _} =
             Forms.get_form_version(ctx.org.id, ctx.version.id, actor: reader)

    assert {:error, %Ash.Error.Forbidden{}} =
             run(FormVersion, :publish, %{ctx | actor: reader}, %{version_id: ctx.version.id})
  end

  test "nested inspection reflects revoked membership with a previously loaded actor", ctx do
    assert [%{id: id}] = Ash.load!(ctx.version, :questions, actor: ctx.actor).questions
    assert id == ctx.question.id
    Organizations.deactivate_membership!(ctx.membership)
    result = Ash.load(ctx.version, :questions, actor: ctx.actor)

    assert match?({:error, %Ash.Error.Forbidden{}}, result) or
             match?({:ok, %{questions: []}}, result)
  end
end
