defmodule QuickTrain.Datasets.RevisionFingerprint do
  @moduledoc false

  import QuickTrain.Datasets.FingerprintEncoding,
    only: [frame: 1, uuid_bytes!: 1, value: 2, digest: 1]

  @domain "quick_train.dataset-revision"
  @version 1

  def encode(schema_version_id, root_record_type_id, occurrences) do
    occurrences = Enum.sort_by(occurrences, &{&1.field.id, &1.ordinal})

    payload =
      [
        frame(@domain),
        frame(<<@version>>),
        frame(uuid_bytes!(schema_version_id)),
        frame(uuid_bytes!(root_record_type_id)),
        frame(Integer.to_string(length(occurrences)))
      ] ++ Enum.map(occurrences, &occurrence_bytes/1)

    digest(payload)
  end

  defp occurrence_bytes(occurrence) do
    frame([
      frame(uuid_bytes!(occurrence.field.id)),
      frame(Atom.to_string(occurrence.family)),
      frame(Integer.to_string(occurrence.ordinal)),
      frame(value(occurrence.family, occurrence.value))
    ])
  end
end
