defmodule QuickTrain.Datasets.Workers.ExpiredOpenImportCleanup do
  # The bounded scan deliberately fails fast on the first cleanup transaction error.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Oban.Worker,
    queue: :dataset_imports,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias QuickTrain.Datasets.DatasetImport.Cleanup

  @page_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    with {:ok, imports} <- Cleanup.expired(now, @page_size) do
      Enum.reduce_while(imports, :ok, fn import, :ok ->
        case Cleanup.cleanup(import.id, now) do
          {:ok, _status} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end
end
