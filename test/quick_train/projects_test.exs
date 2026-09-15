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

  test "native project updates recheck current state and retain explicit stale inputs", context do
    project = ProjectsFixture.configured!(context, context.source)
    Projects.rename_project!(project, %{title: "Changed"}, actor: context.actor)

    assert Projects.rename_project!(project, %{title: project.title}, actor: context.actor).title ==
             project.title

    configured =
      Projects.configure_project!(project, %{submission_target: 2}, actor: context.actor)

    assert configured.submission_target == 2

    unchanged = Projects.configure_project!(project, %{}, actor: context.actor)
    assert unchanged.submission_target == 2
    assert unchanged.title == project.title

    Projects.activate_project!(project, actor: context.actor)

    assert_raise Ash.Error.Invalid, ~r/project_not_draft/, fn ->
      Projects.configure_project!(project, %{title: "Frozen"}, actor: context.actor)
    end

    Organizations.deactivate_membership!(context.membership)

    assert {:error, _} =
             Projects.rename_project(project, %{title: "Denied"}, actor: context.actor)
  end

  test "database identity, management result, and explicit scoped read authority", context do
    project = ProjectsFixture.configured!(context, context.source)
    assert {:ok, id} = Ash.Type.cast_input(:uuid, project.id)
    assert id == project.id

    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).id ==
             project.id

    assert {:error, _} = Ash.read(Project)

    assert {:error, _} =
             Ash.create(Project, %{id: project.id}, action: :create, authorize?: false)

    stranger = Accounts.register_user!("stranger@example.test", "Stranger")
    assert {:error, _} = Projects.get_project(context.org.id, project.id, actor: stranger)

    assert {:error, _} =
             Projects.rename_project(
               project,
               %{
                 title: "No"
               },
               actor: stranger
             )

    assert {:error, _} =
             ProjectItem
             |> Ash.Query.for_read(
               :list_scoped,
               %{organization_id: context.org.id, project_id: project.id},
               actor: stranger
             )
             |> Ash.read()
  end

  test "atomic project batches enforce organization authority and preserve lifecycle retries",
       context do
    projects = for _ <- 1..2, do: ProjectsFixture.active!(context, context.source)

    other =
      ProjectsFixture.context!(
        ~w(projects.manage forms.read forms.manage datasets.read datasets.manage),
        "other-projects"
      )

    foreign = ProjectsFixture.draft!(other, ProjectsFixture.source!(other))

    opts = [
      actor: context.actor,
      strategy: [:atomic],
      authorize_query?: false,
      return_records?: true
    ]

    renamed = Ash.bulk_update!(Project, :rename, %{title: "Renamed"}, opts).records
    assert MapSet.new(renamed, & &1.id) == MapSet.new(projects, & &1.id)
    assert Enum.all?(renamed, &(&1.title == "Renamed"))
    assert Ash.get!(Project, foreign.id, authorize?: false).title == foreign.title

    paused = Ash.bulk_update!(Project, :pause_record, %{}, opts).records
    assert Enum.all?(paused, &(&1.state == :paused))

    retried = Ash.bulk_update!(Project, :pause_record, %{}, opts).records
    assert MapSet.new(retried, &persisted/1) == MapSet.new(paused, &persisted/1)
    assert Ash.get!(Project, foreign.id, authorize?: false).state == :draft

    Organizations.deactivate_membership!(context.membership)
    assert Ash.bulk_update!(Project, :resume_record, %{}, opts).records == []

    for project <- projects do
      assert Ash.get!(Project, project.id, authorize?: false).state == :paused
    end
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
               mutation { activateProject(organizationId: "#{context.org.id}", id: "#{project.id}") {
                 result { id state items(first: 5) { edges { node { id revisionId } } } }
                 errors { message }
               } }
               """,
               QuickTrainWeb.GraphQL.Schema,
               context: %{actor: context.actor}
             )

    refute Map.has_key?(response, :errors)
    assert result["errors"] == []
    result = result["result"]
    assert result["id"] == project.id
    assert result["state"] == "active"
    assert [_, _] = result["items"]["edges"]
  end

  test "enrollment is atomic and cannot mix foreign or newer schema revisions", context do
    project = ProjectsFixture.draft!(context, context.source)
    invalid_id = "00000000-0000-4000-8000-000000000001"

    assert {:error, _} =
             Projects.enroll_revisions(
               context.org.id,
               project.id,
               %{
                 revision_ids: [hd(context.source.revisions).id, invalid_id]
               },
               actor: context.actor
             )

    assert ProjectsFixture.items(project) == []

    Projects.enroll_revisions!(
      context.org.id,
      project.id,
      %{
        revision_ids: Enum.map(context.source.revisions, & &1.id)
      },
      actor: context.actor
    )

    assert {:error, _} =
             Projects.enroll_revisions(
               context.org.id,
               project.id,
               %{
                 revision_ids: [hd(context.source.revisions).id]
               },
               actor: context.actor
             )

    assert [_, _] = ProjectsFixture.items(project)

    other =
      ProjectsFixture.context!(
        ~w(projects.manage forms.read forms.manage datasets.read datasets.manage),
        "other"
      )

    foreign = ProjectsFixture.source!(other)

    assert {:error, _} =
             Projects.set_binding(
               context.org.id,
               project.id,
               %{
                 requirement_id: context.source.form.field.id,
                 field_definition_id: foreign.field.id
               },
               actor: context.actor
             )

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

    assert [first, second] = ProjectsFixture.items(project)

    assert {:error, _} =
             Projects.remove_project_items(
               context.org.id,
               project.id,
               %{project_item_ids: [first.id, invalid_id]},
               actor: context.actor
             )

    assert [_, _] = ProjectsFixture.items(project)

    Projects.remove_project_items!(
      context.org.id,
      project.id,
      %{project_item_ids: [first.id, second.id]},
      actor: context.actor
    )

    assert ProjectsFixture.items(project) == []
  end

  test "source identities are fixed at creation and incompatible bindings fail atomically",
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
             Projects.enroll_revisions(
               context.org.id,
               project.id,
               %{
                 revision_ids: [revision.id]
               },
               actor: context.actor
             )

    assert {:error, _} =
             Projects.configure_project(project, %{schema_version_id: schema.id},
               actor: context.actor
             )

    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).schema_version_id ==
             context.source.schema.id

    assert [_, _] = ProjectsFixture.items(project)

    empty = ProjectsFixture.draft!(context, context.source)

    assert {:error, _} =
             Projects.configure_project(empty, %{schema_version_id: schema.id},
               actor: context.actor
             )

    repinned =
      Projects.create_project!(
        context.org.id,
        %{
          title: "New schema",
          dataset_id: context.source.dataset.id,
          schema_version_id: schema.id,
          form_version_id: context.source.form.version.id
        },
        actor: context.actor
      )

    for field <- [optional, integer] do
      assert {:error, error} =
               Projects.set_binding(
                 context.org.id,
                 repinned.id,
                 %{
                   requirement_id: context.source.form.field.id,
                   field_definition_id: field.id
                 },
                 actor: context.actor
               )

      assert Exception.message(error) =~ "incompatible binding"
    end
  end

  test "activation freezes configuration and lifecycle retries retain exact timestamps",
       context do
    project = ProjectsFixture.configured!(context, context.source)
    active = Projects.activate_project!(project, actor: context.actor)
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

    assert persisted(Projects.activate_project!(project, actor: context.actor)) ==
             persisted(active)

    assert {:error, _} =
             Projects.set_slot_policy(
               context.org.id,
               project.id,
               %{
                 input_slot_id: context.source.form.slot.id,
                 item_count: 1,
                 shuffle: true
               },
               actor: context.actor
             )

    assert {:error, _} =
             Projects.enroll_revisions(
               context.org.id,
               project.id,
               %{
                 revision_ids: [hd(context.source.revisions).id]
               },
               actor: context.actor
             )

    assert Projects.rename_project!(project, %{title: "Renamed"}, actor: context.actor).title ==
             "Renamed"

    for {action, state} <- [
          {&Projects.pause_project!/2, :paused},
          {&Projects.resume_project!/2, :active},
          {&Projects.complete_project!/2, :completed},
          {&Projects.archive_project!/2, :archived}
        ] do
      changed = action.(project, actor: context.actor)
      assert changed.state == state

      assert persisted(action.(project, actor: context.actor)) ==
               persisted(changed)
    end

    assert {:error, error} =
             Projects.resume_project(project, actor: context.actor)

    assert Exception.message(error) =~ "invalid_project_transition"
    Organizations.deactivate_membership!(context.membership)

    assert {:error, _} =
             Projects.archive_project(project, actor: context.actor)
  end

  test "active access overrides remain editable without reopening the configuration", context do
    project = ProjectsFixture.active!(context, context.source)
    worker = Accounts.register_user!("worker@example.test", "Worker")

    for disposition <- [:allow, :block] do
      assert Projects.set_worker_access!(
               context.org.id,
               project.id,
               %{
                 user_id: worker.id,
                 disposition: disposition
               },
               actor: context.actor
             ).state == :active

      row = Ash.read_one!(ProjectWorkerAccess, authorize?: false)
      assert row.disposition == disposition
    end

    Projects.remove_worker_access!(context.org.id, project.id, %{user_id: worker.id},
      actor: context.actor
    )

    assert Ash.count!(ProjectWorkerAccess, authorize?: false) == 0
  end

  test "missing policies leave the draft intact", context do
    project = ProjectsFixture.draft!(context, context.source)

    assert {:error, error} =
             Projects.activate_project(project, actor: context.actor)

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

    assert {:error, error} =
             Projects.activate_project(project, actor: context.actor)

    assert Exception.message(error) =~ "unsupported_task_contract"
    assert Projects.get_project!(context.org.id, project.id, actor: context.actor).state == :draft
  end

  test "explicit groups ignore display order and require coverage of every cohort item",
       context do
    project = ProjectsFixture.configured!(context, context.source, groups: false)
    [first, second] = ProjectsFixture.items(project)
    input = %{input_slot_id: context.source.form.slot.id, project_item_id: first.id, position: 0}

    project =
      Projects.create_explicit_group!(context.org.id, project.id, %{position: 0, inputs: [input]},
        actor: context.actor
      )

    [group] = Ash.load!(project, :explicit_groups, authorize?: false).explicit_groups

    Projects.remove_explicit_group!(context.org.id, project.id, %{group_id: group.id},
      actor: context.actor
    )

    refute Ash.exists?(ExplicitGroup, authorize?: false)
    refute Ash.exists?(QuickTrain.Projects.ExplicitGroupInput, authorize?: false)

    Projects.create_explicit_group!(context.org.id, project.id, %{position: 0, inputs: [input]},
      actor: context.actor
    )

    assert {:error, _} =
             Projects.create_explicit_group(
               context.org.id,
               project.id,
               %{
                 position: 1,
                 inputs: [%{input | position: 99}]
               },
               actor: context.actor
             )

    assert Ash.count!(ExplicitGroup, authorize?: false) == 1

    assert {:error, _} =
             Projects.activate_project(project, actor: context.actor)

    Projects.create_explicit_group!(
      context.org.id,
      project.id,
      %{
        position: 1,
        inputs: [%{input | project_item_id: second.id}]
      },
      actor: context.actor
    )

    assert Projects.activate_project!(project, actor: context.actor).state ==
             :active
  end

  @tag :committed_db
  test "concurrent activation and edits serialize on independent connections", context do
    project = ProjectsFixture.configured!(context, context.source)

    results =
      concurrently([
        fn -> Projects.activate_project(project, actor: context.actor) end,
        fn ->
          Projects.set_slot_policy(
            context.org.id,
            project.id,
            %{
              input_slot_id: context.source.form.slot.id,
              item_count: 1,
              shuffle: true
            },
            actor: context.actor
          )
        end
      ])

    assert {:ok, %{state: :active}} = hd(results)
    policy = Ash.read_one!(Projects.ProjectSlotPolicy, authorize?: false)

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
             Projects.set_slot_policy(
               context.org.id,
               project.id,
               %{
                 input_slot_id: context.source.form.slot.id,
                 item_count: 1,
                 shuffle: false
               },
               actor: context.actor
             )
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

              Projects.set_slot_policy(
                context.org.id,
                project.id,
                %{
                  input_slot_id: context.source.form.slot.id,
                  item_count: 1,
                  shuffle: true
                },
                actor: context.actor
              )
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
    policy = Ash.read_one!(Projects.ProjectSlotPolicy, authorize?: false)
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
