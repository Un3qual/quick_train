defmodule QuickTrain.DatabaseIdentityTest do
  use QuickTrain.DataCase, async: false

  import QuickTrain.FormsFixture

  alias QuickTrain.{Accounts, Assets, Authorization}
  alias QuickTrain.Accounts.User
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.Storage.InMemory
  alias QuickTrain.Authorization.Capability
  alias QuickTrain.Forms.{FormVersion, Graph}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}

  defmodule ObservedStorage do
    defdelegate approved_hosts(), to: InMemory
    defdelegate enforces_byte_cap?(), to: InMemory

    def writable_staging_access(key, cap, expiry) do
      send(self(), {:upload_state, Repo.in_transaction?(), Ash.count!(Asset, authorize?: false)})
      InMemory.writable_staging_access(key, cap, expiry)
    end

    def verify_and_publish(staging_key, sealed_key, expected, deadline) do
      ["assets", "staging", _organization_id, asset_id] = String.split(staging_key, "/")
      asset = Ash.get!(Asset, asset_id, authorize?: false)
      send(self(), {:publication_claim, asset.operation_claim_id, Repo.in_transaction?()})
      InMemory.verify_and_publish(staging_key, sealed_key, expected, deadline)
    end
  end

  test "direct and bulk creates return stored identities and retain existing records" do
    existing = Accounts.register_user!("existing@example.test", "Existing")

    created = Accounts.register_user!("new@example.test", "New")
    assert created.id != existing.id
    assert Ash.get!(User, created.id).email == "new@example.test"

    result =
      Ash.bulk_create!(
        [%{key: "first", description: "First"}, %{key: "second", description: "Second"}],
        Capability,
        :create,
        return_records?: true
      )

    assert Enum.sort(Enum.map(result.records, & &1.key)) == ["first", "second"]
    assert MapSet.size(MapSet.new(result.records, & &1.id)) == 2

    for record <- result.records, do: assert(Ash.get!(Capability, record.id).key == record.key)
    assert Accounts.register_user!(existing.email, "Updated").id == existing.id
    assert Ash.get!(User, existing.id).display_name == "Updated"

    assert {:error, %Ash.Error.Invalid{}} =
             Authorization.create_capability("chosen", "Chosen", %{id: existing.id})
  end

  test "copied graph rows use returned identities and preserve their source" do
    context = context!()
    source = rating!(context)

    other_slot =
      add!(InputSlotDefinition, context, source.version, %{
        key: "other",
        minimum: 1,
        maximum: 1
      })

    add!(InputFieldRequirement, context, source.version, %{
      input_slot_id: other_slot.id,
      key: "summary",
      value_family: :text,
      required: true
    })

    published = run!(FormVersion, :publish, context, %{version_id: source.version.id})
    original = Graph.load!(published.id)

    copied =
      run!(FormVersion, :copy_published, context, %{
        form_id: source.form.id,
        source_version_id: published.id
      })

    assert copied.id != published.id
    graph = Graph.load!(copied.id)
    original_ids = original |> Map.values() |> List.flatten() |> MapSet.new(& &1.id)
    copied_ids = graph |> Map.values() |> List.flatten() |> MapSet.new(& &1.id)
    assert MapSet.disjoint?(original_ids, copied_ids)
    slots = Map.new(graph[InputSlotDefinition], &{&1.key, &1.id})
    fields = Map.new(graph[InputFieldRequirement], &{&1.key, &1.input_slot_id})
    assert fields == %{"body" => slots["item"], "summary" => slots["other"]}
    assert Graph.load!(published.id) == original
    assert run!(FormVersion, :publish, context, %{version_id: copied.id}).state == :published
  end

  test "form creation rejects caller-selected row identities" do
    context = context!()
    %{version: version} = draft!(context)

    assert {:error, %Ash.Error.Invalid{}} =
             InputSlotDefinition
             |> Ash.Changeset.for_create(:create_internal, %{
               id: Ash.UUID.generate(),
               version_id: version.id,
               key: "chosen",
               minimum: 1,
               maximum: 1
             })
             |> Ash.create(authorize?: false)

    assert Ash.count!(InputSlotDefinition, authorize?: false) == 0
  end

  test "asset registration preserves its staging identity and keeps storage I/O outside transactions" do
    context = context!(~w(assets.read assets.manage))
    :ok = InMemory.reset()
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(config, :storage_adapter, ObservedStorage)
    )

    content = "registered asset"

    registration =
      Assets.register_asset!(
        context.org.id,
        Base.encode16(:crypto.hash(:sha256, content), case: :lower),
        byte_size(content),
        "text/plain",
        actor: context.actor
      )

    stored = Ash.get!(Asset, registration.asset.id, authorize?: false)
    assert stored.staging_key == "assets/staging/#{context.org.id}/#{registration.asset.id}"
    assert_received {:upload_state, false, 0}
    assert :ok = InMemory.put_staging(registration.upload_access, content)

    final = Assets.finalize_asset!(stored.id, context.org.id, actor: context.actor)
    assert_received {:publication_claim, claim_id, false}
    assert {:ok, ^claim_id} = Ash.Type.cast_input(:uuid, claim_id)
    assert claim_id != stored.id
    assert final.asset.id == stored.id
    assert final.asset.state == :ready
  end
end
