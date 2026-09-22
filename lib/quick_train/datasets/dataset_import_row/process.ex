defmodule QuickTrain.Datasets.DatasetImportRow.Process do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias QuickTrain.Datasets.{DatasetImportRow, DatasetRecord}

  @impl true
  def run(%{action: %{name: :process_internal}, arguments: %{row_id: row_id}}, _opts, _context),
    do: process(row_id)

  defp process(row_id) do
    Ash.transact([DatasetImportRow, DatasetRecord], fn ->
      case locked_row(row_id) do
        nil ->
          :missing

        %{outcome: outcome} when outcome != :pending ->
          :terminal

        row ->
          create_revision_and_complete(row)
          :processed
      end
    end)
  end

  defp create_revision_and_complete(row) do
    result =
      QuickTrain.Datasets.put_candidate_revision!(
        row.organization_id,
        row.dataset_id,
        row.schema_version_id,
        if(row.external_key, do: nil, else: row.id),
        row.external_key,
        row.candidate_record_id,
        authorize?: false
      )

    outcome = if result.changed, do: :succeeded, else: :unchanged

    QuickTrain.Datasets.complete_import_row_internal!(
      row,
      %{
        outcome: outcome,
        error_code: nil,
        item_revision_id: result.revision.id
      },
      authorize?: false
    )
  end

  defp locked_row(row_id),
    do:
      QuickTrain.Datasets.get_import_row_internal!(row_id,
        query: [lock: :for_update],
        authorize?: false
      )
end
