defmodule QuickTrain.ProjectsTest do
  use QuickTrain.DataCase, async: false
  alias QuickTrain.{Accounts, Organizations, Projects, ProjectsFixture}

  alias QuickTrain.Projects.{
    ExplicitGroup,
    Management,
    Project,
    ProjectInputBinding,
    ProjectItem,
    ProjectWorkerAccess
  }

  setup do
    context = ProjectsFixture.context!()
    source = ProjectsFixture.source!(context)
    Map.merge(context, %{source: source})
  end

  test "database identity, management result, and explicit scoped read authority", context do
    project = ProjectsFixture.configured!(context, context.source)
    assert {:ok, id} = Ash.Type.cast_input(:uuid, project.id)
    assert id == project.id

    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).id ==
             project.id

    assert {:error, _} = Ash.read(Project)

    assert {:error, _} =
             Ash.create(Project, %{id: project.id}, action: :create_internal, authorize?: false)

    stranger = Accounts.register_user!("stranger@example.test", "Stranger")
    assert {:error, _} = Projects.get_project(context.org.id, project.id, actor: stranger)

    assert {:error, _} =
             ProjectsFixture.run(%{context | actor: stranger}, project, :update_title, %{
               title: "No"
             })

    assert {:error, _} =
             ProjectItem
             |> Ash.Query.for_read(
               :list_scoped,
               %{organization_id: context.org.id, project_id: project.id},
               actor: stranger
             )
             |> Ash.read()
  end

  test "manage-only capability authorizes mutation results without general inspection",
       _context do
    context =
      ProjectsFixture.context!(
        ~w(projects.manage forms.read forms.manage datasets.read datasets.manage),
        "manage-only"
      )

    source = ProjectsFixture.source!(context)
    project = ProjectsFixture.configured!(context, source)
    assert project.title == "Collection"
    assert {:error, _} = Projects.get_project(context.org.id, project.id, actor: context.actor)

    assert {:ok, %{data: %{"activateProject" => result}} = response} =
             Absinthe.run(
               """
               mutation { activateProject(organizationId: "#{context.org.id}", projectId: "#{project.id}") {
                 id state items(first: 5) { edges { node { id revisionId } } }
               } }
               """,
               QuickTrainWeb.GraphQL.Schema,
               context: %{actor: context.actor}
             )

    refute Map.has_key?(response, :errors)
    assert result["id"] == project.id
    assert result["state"] == "active"
    assert [_, _] = result["items"]["edges"]
  end

  test "enrollment is atomic and cannot mix foreign or newer schema revisions", context do
    project = ProjectsFixture.draft!(context, context.source)
    invalid_id = "00000000-0000-4000-8000-000000000001"

    assert {:error, _} =
             ProjectsFixture.run(context, project, :enroll_revisions, %{
               revision_ids: [hd(context.source.revisions).id, invalid_id]
             })

    assert ProjectsFixture.items(project) == []

    ProjectsFixture.run!(context, project, :enroll_revisions, %{
      revision_ids: Enum.map(context.source.revisions, & &1.id)
    })

    assert {:error, _} =
             ProjectsFixture.run(context, project, :enroll_revisions, %{
               revision_ids: [hd(context.source.revisions).id]
             })

    assert [_, _] = ProjectsFixture.items(project)

    other =
      ProjectsFixture.context!(
        ~w(projects.manage forms.read forms.manage datasets.read datasets.manage),
        "other"
      )

    foreign = ProjectsFixture.source!(other)

    assert {:error, _} =
             ProjectsFixture.run(context, project, :set_binding, %{
               requirement_id: context.source.form.field.id,
               field_definition_id: foreign.field.id
             })

    assert Ash.count!(ProjectInputBinding, authorize?: false) == 0
    revision = hd(foreign.revisions)

    assert {:error, _} =
             Ash.create(
               ProjectItem,
               %{
                 project_id: project.id,
                 dataset_id: project.dataset_id,
                 schema_version_id: project.schema_version_id,
                 item_id: revision.item_id,
                 revision_id: revision.id
               },
               action: :create_internal,
               authorize?: false
             )

    assert [_, _] = ProjectsFixture.items(project)
  end

  test "draft repinning, mixed schemas, and binding family/requiredness fail atomically",
       context do
    alias QuickTrain.Datasets
    project = ProjectsFixture.configured!(context, context.source)

    schema =
      Datasets.create_schema_version!(context.org.id, context.source.dataset.id,
        actor: context.actor
      )

    root =
      Datasets.add_record_type!(context.org.id, schema.id, "item", "Item", actor: context.actor)

    optional =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "body",
        "Body",
        "text",
        "single",
        false,
        actor: context.actor
      )

    integer =
      Datasets.add_field_definition!(
        context.org.id,
        root.id,
        "number",
        "Number",
        "integer",
        "single",
        true,
        actor: context.actor
      )

    schema =
      Datasets.publish_schema_version!(context.org.id, schema.id, root.id, actor: context.actor)

    revision =
      Datasets.put_item_revision!(
        context.org.id,
        context.source.dataset.id,
        schema.id,
        nil,
        "new-schema",
        [%{field: "body", text: "Body"}, %{field: "number", integer: 3}],
        actor: context.actor
      ).revision

    assert {:error, _} =
             ProjectsFixture.run(context, project, :enroll_revisions, %{
               revision_ids: [revision.id]
             })

    assert {:error, _} =
             ProjectsFixture.run(context, project, :update_draft, %{schema_version_id: schema.id})

    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).schema_version_id ==
             context.source.schema.id

    assert [_, _] = ProjectsFixture.items(project)

    empty = ProjectsFixture.draft!(context, context.source)

    repinned =
      ProjectsFixture.run!(context, empty, :update_draft, %{schema_version_id: schema.id})

    assert repinned.schema_version_id == schema.id
    assert repinned.root_record_type_id == root.id

    for field <- [optional, integer] do
      assert {:error, error} =
               ProjectsFixture.run(context, repinned, :set_binding, %{
                 requirement_id: context.source.form.field.id,
                 field_definition_id: field.id
               })

      assert Exception.message(error) =~ "incompatible binding"
    end
  end

  test "activation freezes configuration and lifecycle retries retain exact timestamps",
       context do
    project = ProjectsFixture.configured!(context, context.source)
    active = ProjectsFixture.run!(context, project, :activate)
    assert active.state == :active

    later =
      QuickTrain.Datasets.put_item_revision!(
        context.org.id,
        context.source.dataset.id,
        context.source.schema.id,
        nil,
        "item-1",
        [%{field: "body", text: "New revision"}],
        actor: context.actor
      ).revision

    refute later.id in Enum.map(ProjectsFixture.items(project), & &1.revision_id)

    assert MapSet.new(ProjectsFixture.items(project), & &1.revision_id) ==
             MapSet.new(context.source.revisions, & &1.id)

    assert persisted(ProjectsFixture.run!(context, project, :activate)) == persisted(active)

    assert {:error, _} =
             ProjectsFixture.run(context, project, :set_slot_policy, %{
               input_slot_id: context.source.form.slot.id,
               item_count: 1,
               shuffle: true
             })

    assert {:error, _} =
             ProjectsFixture.run(context, project, :enroll_revisions, %{
               revision_ids: [hd(context.source.revisions).id]
             })

    assert ProjectsFixture.run!(context, project, :update_title, %{title: "Renamed"}).title ==
             "Renamed"

    for {action, state} <- [
          pause: :paused,
          resume: :active,
          complete: :completed,
          archive: :archived
        ] do
      changed = ProjectsFixture.run!(context, project, action)
      assert changed.state == state
      assert persisted(ProjectsFixture.run!(context, project, action)) == persisted(changed)
    end

    assert {:error, _} = ProjectsFixture.run(context, project, :resume)
    Organizations.deactivate_membership!(context.membership)
    assert {:error, _} = ProjectsFixture.run(context, project, :archive)
  end

  test "active access overrides remain editable without reopening the configuration", context do
    project = ProjectsFixture.active!(context, context.source)
    worker = Accounts.register_user!("worker@example.test", "Worker")

    for disposition <- [:allow, :block] do
      assert ProjectsFixture.run!(context, project, :set_worker_access, %{
               user_id: worker.id,
               disposition: disposition
             }).state == :active

      row = Ash.read_one!(ProjectWorkerAccess, authorize?: false)
      assert row.disposition == disposition
    end

    ProjectsFixture.run!(context, project, :remove_worker_access, %{user_id: worker.id})
    assert Ash.count!(ProjectWorkerAccess, authorize?: false) == 0
  end

  test "missing policies leave the draft intact", context do
    project = ProjectsFixture.draft!(context, context.source)
    assert {:error, error} = ProjectsFixture.run(context, project, :activate)
    assert Exception.message(error) =~ "invalid_project_configuration"
    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).state == :draft
  end

  test "mixed image requirements are rejected before any work contract is frozen", _context do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage),
        "images"
      )

    source = ProjectsFixture.source!(context, image_requirement: true)
    project = ProjectsFixture.configured!(context, source)
    assert {:error, error} = ProjectsFixture.run(context, project, :activate)
    assert Exception.message(error) =~ "unsupported_task_contract"
    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).state == :draft
  end

  test "explicit groups ignore display order and require coverage of every cohort item",
       context do
    project = ProjectsFixture.configured!(context, context.source, selection_mode: :explicit)
    [first, second] = ProjectsFixture.items(project)
    input = %{input_slot_id: context.source.form.slot.id, project_item_id: first.id, position: 0}

    ProjectsFixture.run!(context, project, :create_explicit_group, %{position: 0, inputs: [input]})

    assert {:error, _} =
             ProjectsFixture.run(context, project, :create_explicit_group, %{
               position: 1,
               inputs: [%{input | position: 99}]
             })

    assert Ash.count!(ExplicitGroup, authorize?: false) == 1
    assert {:error, _} = ProjectsFixture.run(context, project, :activate)

    ProjectsFixture.run!(context, project, :create_explicit_group, %{
      position: 1,
      inputs: [%{input | project_item_id: second.id}]
    })

    assert ProjectsFixture.run!(context, project, :activate).state == :active
  end

  @tag :committed_db
  test "concurrent activation and edits serialize on independent connections", context do
    project = ProjectsFixture.configured!(context, context.source)

    results =
      concurrently([
        fn -> ProjectsFixture.run(context, project, :activate) end,
        fn ->
          ProjectsFixture.run(context, project, :set_slot_policy, %{
            input_slot_id: context.source.form.slot.id,
            item_count: 1,
            shuffle: true
          })
        end
      ])

    assert {:ok, %{state: :active}} = hd(results)
    policy = Ash.read_one!(QuickTrain.Projects.ProjectSlotPolicy, authorize?: false)

    case Enum.at(results, 1) do
      {:ok, _} ->
        assert policy.shuffle

      {:error, error} ->
        assert Exception.message(error) =~ "project_not_draft"
        refute policy.shuffle
    end

    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).state ==
             :active

    assert {:error, _} =
             ProjectsFixture.run(context, project, :set_slot_policy, %{
               input_slot_id: context.source.form.slot.id,
               item_count: 1,
               shuffle: false
             })
  end

  @tag :committed_db
  test "a waiting child edit rechecks membership after acquiring the project lock", context do
    project = ProjectsFixture.configured!(context, context.source)
    parent = self()

    {:ok, {task, notifications}} =
      Repo.transaction(fn ->
        Management.lock!(context.org.id, project.id)

        task =
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              %{rows: [[backend_id]]} = Repo.query!("SELECT pg_backend_pid()")
              send(parent, {:editor_connection, backend_id})

              ProjectsFixture.run(context, project, :set_slot_policy, %{
                input_slot_id: context.source.form.slot.id,
                item_count: 1,
                shuffle: true
              })
            end)
          end)

        assert_receive {:editor_connection, backend_id}, 5_000
        await_project_lock(backend_id, System.monotonic_time(:millisecond) + 5_000)

        {_membership, notifications} =
          Organizations.deactivate_membership!(context.membership, return_notifications?: true)

        {task, notifications}
      end)

    Ash.Notifier.notify(notifications)
    assert {:error, _} = Task.await(task, 10_000)
    policy = Ash.read_one!(QuickTrain.Projects.ProjectSlotPolicy, authorize?: false)
    refute policy.shuffle
  end

  test "activation and cohort inspection traverse beyond one page", _context do
    context =
      ProjectsFixture.context!(
        ~w(projects.read projects.manage forms.read forms.manage datasets.read datasets.manage),
        "large"
      )

    source = ProjectsFixture.source!(context, item_count: 105)
    project = ProjectsFixture.active!(context, source)

    query =
      ProjectItem
      |> Ash.Query.for_read(
        :list_scoped,
        %{organization_id: context.org.id, project_id: project.id},
        actor: context.actor
      )

    first = Ash.read!(query, page: [limit: 100])
    assert Enum.count_until(first.results, 101) == 100
    second = Ash.page!(first, :next)
    assert [_, _, _, _, _] = second.results

    assert MapSet.new(first.results ++ second.results, & &1.revision_id) ==
             MapSet.new(source.revisions, & &1.id)
  end

  defp persisted(record),
    do: Map.take(record, Enum.to_list(Ash.Resource.Info.attribute_names(Project)))

  defp await_project_lock(backend_id, deadline) do
    %{rows: [[waiting]]} =
      Repo.query!("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = $1", [
        backend_id
      ])

    cond do
      waiting ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("editor did not reach the project lock")

      true ->
        Process.sleep(10)
        await_project_lock(backend_id, deadline)
    end
  end
end
