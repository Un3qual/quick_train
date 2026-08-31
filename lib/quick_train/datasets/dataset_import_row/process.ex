defmodule QuickTrain.Datasets.DatasetImportRow.Process do
  @moduledoc false

  require Ash.Query

  alias QuickTrain.Datasets.{DatasetImportRow, DatasetRecord}
  alias QuickTrain.Datasets.DatasetImportRow.CandidateInput

  def process(row_id) do
    Ash.transact([DatasetImportRow, DatasetRecord], fn ->
      case locked_row(row_id) do
        nil ->
          :missing

        %{outcome: outcome} when outcome != :pending ->
          :terminal

        row ->
          create_revision_and_complete(row)
      end
    end)
  end

  def terminalize(row_id, error_code \\ "processing_retries_exhausted") do
    Ash.transact(DatasetImportRow, fn ->
      case locked_row(row_id) do
        %{outcome: :pending} = row ->
          row
          |> Ash.Changeset.for_update(:complete_internal, %{
            outcome: :failed,
            error_code: error_code,
            item_revision_id: nil
          })
          |> Ash.update!(authorize?: false)

          :terminalized

        _other ->
          :skipped
      end
    end)
  end

  defp create_revision_and_complete(row) do
    record = Ash.get!(DatasetRecord, row.candidate_record_id, authorize?: false)
    values = CandidateInput.from_record(record)

    result =
      QuickTrain.Datasets.put_item_revision!(
        row.organization_id,
        row.dataset_id,
        row.schema_version_id,
        if(row.external_key, do: nil, else: row.id),
        row.external_key,
        values,
        authorize?: false
      )

    outcome = if result.changed, do: :succeeded, else: :unchanged

    row
    |> Ash.Changeset.for_update(:complete_internal, %{
      outcome: outcome,
      error_code: nil,
      item_revision_id: result.revision.id
    })
    |> Ash.update!(authorize?: false)
  end

  defp locked_row(row_id) do
    DatasetImportRow
    |> Ash.Query.filter(id == ^row_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end
end
