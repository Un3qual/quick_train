defmodule QuickTrain.Tasks.Exports.Snapshot do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Repo
  alias QuickTrain.Tasks
  alias QuickTrain.Tasks.Access
  alias QuickTrain.Tasks.Attempts.Leases
  alias QuickTrain.Tasks.Exports.{ExportSelection, ResultExport}
  alias QuickTrain.Tasks.Responses.QuestionResponse
  alias QuickTrain.Tasks.Reviews.ReviewDecision
  require Ash.Query

  @impl true
  def run(%{arguments: %{id: id}}, _opts, _context) do
    Ash.transact([ResultExport, ExportSelection], fn ->
      # This must be the transaction's first statement: every page sees one
      # committed MVCC snapshot, including submissions concurrent with selection.
      Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

      export =
        Tasks.get_result_export_internal!(id,
          query: [lock: :for_update],
          authorize?: false
        )
        |> Access.found!()

      if export.snapshot_at do
        export
      else
        project = Access.project!(export.organization_id, export.project_id)
        Access.manager!(project, %{id: export.requester_id}, "tasks.results.read")
        select!(export)

        count =
          Ash.count!(ExportSelection, query: [filter: [export_id: export.id]], authorize?: false)

        Ash.update!(
          export,
          %{
            state: :writing,
            snapshot_at: Leases.now!(),
            record_count: count,
            error_code: nil
          },
          action: :update_internal,
          authorize?: false
        )
      end
    end)
  end

  defp select!(export) do
    QuestionResponse
    |> Ash.Query.filter(
      project_id == ^export.project_id and attempt.state == :submitted and
        (^export.mode == :audit or effective_verdict == :accept)
    )
    |> Ash.Query.select([:id, :task_id, :question_id])
    |> Ash.Query.load(effective_decision: Ash.Query.select(ReviewDecision, [:id]))
    |> stream()
    |> Stream.map(fn outcome ->
      %{
        export_id: export.id,
        organization_id: export.organization_id,
        project_id: export.project_id,
        form_version_id: export.form_version_id,
        task_id: outcome.task_id,
        question_id: outcome.question_id,
        question_response_id: outcome.id,
        decision_id: outcome.effective_decision && outcome.effective_decision.id
      }
    end)
    |> Ash.bulk_create!(ExportSelection, :create_internal,
      authorize?: false,
      transaction: :all,
      stop_on_error?: true
    )
  end

  def rows(export) do
    ExportSelection
    |> Ash.Query.filter(export_id == ^export.id)
    |> Ash.Query.sort(question_response_id: :asc)
    |> Ash.Query.load([:decision, question_response: [:attempt, :task]])
    |> Ash.stream!(batch_size: 100, authorize?: false)
  end

  defp stream(query),
    do: query |> Ash.Query.sort(id: :asc) |> Ash.stream!(batch_size: 100, authorize?: false)
end
