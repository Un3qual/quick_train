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

  @prefix "00000000-0000-4000-8000-"

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

  setup do
    # A controlled PostgreSQL generator proves the application uses the database's value.
    # The sandbox rolls back this schema and each altered table default after the test.
    Repo.query!("CREATE SCHEMA identity_test")
    Repo.query!("CREATE SEQUENCE identity_test.identities")

    Repo.query!("""
    CREATE FUNCTION identity_test.gen_random_uuid() RETURNS uuid LANGUAGE SQL AS $$
      SELECT ('#{@prefix}' || lpad(nextval('identity_test.identities')::text, 12, '0'))::uuid
    $$
    """)

    :ok
  end

  test "direct and bulk creates return stored database identities and retain existing records" do
    existing = Accounts.register_user!("existing@example.test", "Existing")
    database_default!("users")
    database_default!("capabilities")

    created = Accounts.register_user!("new@example.test", "New")
    assert created.id == @prefix <> "000000000001"
    assert Ash.get!(User, created.id).email == "new@example.test"

    result =
      Ash.bulk_create!(
        [%{key: "first", description: "First"}, %{key: "second", description: "Second"}],
        Capability,
        :create,
        return_records?: true
      )

    assert MapSet.new(result.records, & &1.id) ==
             MapSet.new([@prefix <> "000000000002", @prefix <> "000000000003"])

    for record <- result.records, do: assert(Ash.get!(Capability, record.id).key == record.key)
    assert Accounts.register_user!(existing.email, "Updated").id == existing.id
    assert Ash.get!(User, existing.id).display_name == "Updated"

    assert {:error, %Ash.Error.Invalid{}} =
             Authorization.create_capability("chosen", "Chosen", %{id: existing.id})
  end

  test "copied graph rows use returned database identities and preserve their source" do
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

    for resource <- [FormVersion | Graph.resources()] do
      database_default!(AshPostgres.DataLayer.Info.table(resource))
    end

    copied =
      run!(FormVersion, :copy_published, context, %{
        form_id: source.form.id,
        source_version_id: published.id
      })

    assert copied.id == @prefix <> "000000000001"
    graph = Graph.load!(copied.id)
    assert Enum.all?(List.flatten(Map.values(graph)), &String.starts_with?(&1.id, @prefix))
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
               id: @prefix <> "000000000001",
               version_id: version.id,
               key: "chosen",
               minimum: 1,
               maximum: 1
             })
             |> Ash.create(authorize?: false)

    assert Ash.count!(InputSlotDefinition, authorize?: false) == 0
  end

  test "ordinary asset registration and claim retain PostgreSQL-issued UUIDs outside storage I/O" do
    context = context!(~w(assets.read assets.manage))
    :ok = InMemory.reset()
    config = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.put_env(:quick_train, :assets, config) end)

    Application.put_env(
      :quick_train,
      :assets,
      Keyword.put(config, :storage_adapter, ObservedStorage)
    )

    Repo.query!("SET LOCAL search_path TO identity_test, public, pg_catalog")
    content = "database-issued asset"

    registration =
      Assets.register_asset!(
        context.org.id,
        Base.encode16(:crypto.hash(:sha256, content), case: :lower),
        byte_size(content),
        "text/plain",
        actor: context.actor
      )

    assert registration.asset.id == @prefix <> "000000000001"
    stored = Ash.get!(Asset, registration.asset.id, authorize?: false)
    assert stored.staging_key == "assets/staging/#{context.org.id}/#{registration.asset.id}"
    assert_received {:upload_state, false, 0}
    assert :ok = InMemory.put_staging(registration.upload_access, content)

    final = Assets.finalize_asset!(stored.id, context.org.id, actor: context.actor)
    assert_received {:publication_claim, @prefix <> "000000000002", false}
    assert final.asset.id == stored.id
    assert final.asset.state == :ready

    Repo.query!("""
    CREATE OR REPLACE FUNCTION identity_test.gen_random_uuid() RETURNS uuid LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'injected_uuid_failure'; END;
    $$
    """)

    assert {:error, _error} =
             Assets.register_asset(
               context.org.id,
               Base.encode16(:crypto.hash(:sha256, "different"), case: :lower),
               9,
               "text/plain",
               actor: context.actor
             )

    refute_received {:upload_state, _, _}
    assert Ash.count!(Asset, authorize?: false) == 1
  end

  defp database_default!(table) do
    Repo.query!(
      "ALTER TABLE #{table} ALTER COLUMN id SET DEFAULT identity_test.gen_random_uuid()"
    )
  end
end
