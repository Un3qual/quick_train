defmodule QuickTrain.Datasets.ImportRowFingerprint do
  @moduledoc false

  alias QuickTrain.Datasets.RevisionFingerprint

  @domain "quick_train.dataset-import-row"
  @version 1

  def encode(schema_version_id, row_key, external_key, source_position, entries) do
    entries = Enum.sort_by(entries, &{&1.field, &1.family, canonical_value(&1)})

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
        frame([frame(entry.field), frame(entry.family), frame(canonical_value(entry))])
      end)
    ]

    payload
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_value(%{family: "text", value: value}), do: value
  defp canonical_value(%{family: "integer", value: value}), do: Integer.to_string(value)

  defp canonical_value(%{family: "decimal", value: value}),
    do: RevisionFingerprint.canonical_decimal(value)

  defp canonical_value(%{family: "boolean", value: true}), do: <<1>>
  defp canonical_value(%{family: "boolean", value: false}), do: <<0>>

  defp canonical_value(%{family: "utc_datetime", value: value}),
    do: Integer.to_string(DateTime.to_unix(value, :microsecond))

  defp canonical_value(%{family: "asset", value: value}), do: uuid_bytes!(value)

  defp uuid_bytes!(uuid) do
    {:ok, bytes} = Ecto.UUID.dump(uuid)
    bytes
  end

  defp frame(value) do
    bytes = IO.iodata_to_binary(value)
    [<<byte_size(bytes)::unsigned-big-32>>, bytes]
  end
end
