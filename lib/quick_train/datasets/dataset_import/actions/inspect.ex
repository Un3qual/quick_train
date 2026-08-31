defmodule QuickTrain.Datasets.DatasetImport.Actions.Inspect do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImport, DatasetImportRow, DatasetImportSummary}

  @impl true
  def run(input, _opts, _context) do
    arguments = input.arguments

    case DatasetImport
         |> Ash.Query.filter(
           id == ^arguments.import_id and organization_id == ^arguments.organization_id
         )
         |> Ash.read_one!(authorize?: false) do
      nil -> {:error, :invalid_import}
      import -> {:ok, summary(import)}
    end
  end

  defp summary(import) do
    counts =
      for outcome <- ~w(pending succeeded unchanged failed), into: %{} do
        count =
          DatasetImportRow
          |> Ash.Query.filter(import_id == ^import.id and outcome == ^outcome)
          |> Ash.count!(authorize?: false)

        {String.to_atom(outcome), count}
      end

    row_count = Enum.sum(Map.values(counts))

    struct!(DatasetImportSummary, %{
      import_id: import.id,
      phase: import.phase,
      lifecycle: lifecycle(import.phase, row_count, counts),
      row_count: row_count,
      pending: counts.pending,
      succeeded: counts.succeeded,
      unchanged: counts.unchanged,
      failed: counts.failed
    })
  end

  defp lifecycle("open", _row_count, _counts), do: "open"
  defp lifecycle("sealed", _row_count, %{pending: pending}) when pending > 0, do: "pending"
  defp lifecycle("sealed", 0, _counts), do: "completed"

  defp lifecycle("sealed", row_count, %{failed: failed}) when failed == row_count,
    do: "failed"

  defp lifecycle("sealed", _row_count, %{failed: failed}) when failed > 0,
    do: "partially_failed"

  defp lifecycle("sealed", _row_count, _counts), do: "completed"
end
