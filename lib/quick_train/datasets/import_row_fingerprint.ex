defmodule QuickTrain.Datasets.ImportRowFingerprint do
  @moduledoc false

  import QuickTrain.Datasets.FingerprintEncoding,
    only: [frame: 1, uuid_bytes!: 1, value: 2, digest: 1]

  @domain "quick_train.dataset-import-row"
  @version 1

  def encode(schema_version_id, row_key, external_key, source_position, entries) do
    entries = Enum.sort_by(entries, &{&1.field, &1.family, value(&1.family, &1.value)})

    payload = [
      frame(@domain),
      frame(<<@version>>),
      frame(uuid_bytes!(schema_version_id)),
      frame(row_key),
      frame(if(is_nil(external_key), do: <<0>>, else: <<1>>)),
      frame(external_key || ""),
      frame(Integer.to_string(source_position)),
      frame(Integer.to_string(length(entries))),
      Enum.map(entries, fn entry ->
        frame([
          frame(entry.field),
          frame(Atom.to_string(entry.family)),
          frame(value(entry.family, entry.value))
        ])
      end)
    ]

    digest(payload)
  end
end
