defmodule QuickTrain.Forms.FormConcurrencyTest do
  use QuickTrain.DataCase, async: false
  @moduletag :committed_db
  import QuickTrain.FormsFixture
  alias Ecto.Adapters.SQL.Sandbox

  alias QuickTrain.Forms.{
    AnnotationConstraints,
    FormVersion,
    InputFieldRequirement,
    LabelSet,
    QuestionDefinition
  }

  setup do
    ctx = context!()
    Map.merge(ctx, rating!(ctx))
  end

  test "empty creation and copying serialize allocation in commit order", ctx do
    run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})

    [first, second] =
      race(
        "forms",
        fn -> run(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}) end,
        fn ->
          run(FormVersion, :copy_published, ctx, %{
            form_id: ctx.form.id,
            source_version_id: ctx.version.id
          })
        end
      )

    assert {:ok, %{version: 2}} = first
    assert {:ok, %{version: 3}} = second
  end

  test "rollback completes before a waiting allocator reuses its uncommitted number", ctx do
    run!(FormVersion, :publish, ctx, %{version_id: ctx.version.id})

    [first, second] =
      race(
        "forms",
        fn ->
          Ash.transact(FormVersion, fn ->
            run!(FormVersion, :copy_published, ctx, %{
              form_id: ctx.form.id,
              source_version_id: ctx.version.id
            })

            {:error, :deliberate_rollback}
          end)
        end,
        fn -> run(FormVersion, :create_draft, ctx, %{form_id: ctx.form.id}) end
      )

    assert {:error, error} = first
    assert Exception.message(error) =~ "deliberate_rollback"
    assert {:ok, %{version: 2}} = second
    assert Ash.count!(FormVersion, authorize?: false) == 2
    assert Ash.count!(QuestionDefinition, authorize?: false) == 1
  end

  test "concurrent publication converges on one immutable timestamp", ctx do
    operation = fn -> run(FormVersion, :publish, ctx, %{version_id: ctx.version.id}) end
    [{:ok, first}, {:ok, second}] = race("form_versions", operation, operation)
    assert first.id == second.id
    assert first.published_at == second.published_at
  end

  for edit_first? <- [true, false] do
    test "child edit/publication serialize with edit first = #{edit_first?}", ctx do
      editor = fn -> edit(QuestionDefinition, ctx, ctx.question, %{prompt: "Edited"}) end
      publisher = fn -> run(FormVersion, :publish, ctx, %{version_id: ctx.version.id}) end

      if unquote(edit_first?) do
        assert [{:ok, _}, {:ok, _}] = race("form_versions", editor, publisher)
        assert Ash.get!(QuestionDefinition, ctx.question.id, authorize?: false).prompt == "Edited"
      else
        assert [{:ok, _}, {:error, _}] = race("form_versions", publisher, editor)

        assert Ash.get!(QuestionDefinition, ctx.question.id, authorize?: false).prompt ==
                 ctx.question.prompt
      end
    end
  end

  for source_first? <- [true, false] do
    test "source edits and inbound references serialize with source first = #{source_first?}",
         ctx do
      image =
        add!(InputFieldRequirement, ctx, ctx.version, %{
          key: "image",
          input_slot_id: ctx.slot.id,
          value_family: :asset,
          intended_use: :image,
          required: true
        })

      labels = add!(LabelSet, ctx, ctx.version, %{key: "labels"})

      question =
        add!(QuestionDefinition, ctx, ctx.version, %{
          key: "boxes",
          prompt: "Boxes",
          family: :bounding_boxes,
          renderer: :bounding_boxes
        })

      source_edit = fn -> edit(InputFieldRequirement, ctx, image, %{intended_use: :download}) end

      reference_edit = fn ->
        run(AnnotationConstraints, :add_to_draft, ctx, %{
          version_id: ctx.version.id,
          question_id: question.id,
          source_requirement_id: image.id,
          label_set_id: labels.id,
          minimum: 0,
          maximum: 10
        })
      end

      [first, second] =
        if unquote(source_first?),
          do: [source_edit, reference_edit],
          else: [reference_edit, source_edit]

      assert [{:ok, _}, {:error, _}] =
               race("form_versions", first, second)
    end
  end

  defp race(table, first, second) do
    handler = "form-race-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:quick_train, :repo, :query],
        fn _event, _measurements, metadata, _ ->
          if Process.get(:form_test_lock) == table and
               String.contains?(metadata.query, "FOR UPDATE") and
               String.contains?(metadata.query, ~s(FROM "#{table}")) do
            Process.delete(:form_test_lock)
            send(parent, {:locked, self()})

            receive do
              :release -> :ok
            after
              10_000 -> raise "lock barrier timed out"
            end
          end
        end,
        nil
      )

    first_task = start_connection(first, table)

    try do
      assert_receive {:ready, first_pid, first_backend}, 5_000
      assert first_pid == first_task.pid
      send(first_pid, :start)
      assert_receive {:locked, ^first_pid}, 5_000
      second_task = start_connection(second, nil)

      try do
        assert_receive {:ready, second_pid, second_backend}, 5_000
        assert second_pid == second_task.pid
        refute second_backend == first_backend
        send(second_pid, :start)
        await_blocked(second_backend, first_backend, System.monotonic_time(:millisecond) + 5_000)
        send(first_pid, :release)
        Task.await_many([first_task, second_task], 15_000)
      after
        Task.shutdown(second_task, :brutal_kill)
      end
    after
      Task.shutdown(first_task, :brutal_kill)
      :telemetry.detach(handler)
    end
  end

  defp start_connection(operation, lock_table) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Process.put(:form_test_lock, lock_table)
        %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
        send(parent, {:ready, self(), backend})
        receive do: (:start -> operation.())
      end)
    end)
  end

  defp await_blocked(waiter, blocker, deadline) do
    %{rows: [[blocked?]]} =
      Repo.query!("SELECT $1::int = ANY(pg_blocking_pids($2::int))", [blocker, waiter])

    unless blocked? do
      assert System.monotonic_time(:millisecond) < deadline,
             "second connection never waited on the owning row lock"

      Process.sleep(10)
      await_blocked(waiter, blocker, deadline)
    end
  end
end
