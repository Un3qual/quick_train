defmodule QuickTrain.Datasets.Fingerprint do
  @moduledoc "Version-one dataset fingerprints with stable canonical encoding."

  def revision(schema_version_id, root_record_type_id, occurrences) do
    occurrences = Enum.sort_by(occurrences, &{&1.field.id, &1.ordinal})

    payload =
      [
        frame("quick_train.dataset-revision"),
        frame(<<1>>),
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

  def import_row(schema_version_id, row_key, external_key, source_position, entries) do
    entries = Enum.sort_by(entries, &{&1.field, &1.family, value(&1.family, &1.value)})

    payload = [
      frame("quick_train.dataset-import-row"),
      frame(<<1>>),
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

  def import_open(schema_version_id, actor_id) do
    digest("quick_train.dataset-import-open:v1:#{schema_version_id}:#{actor_id}")
  end

  defp digest(payload) do
    payload
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def canonical_decimal(%Decimal{} = decimal) do
    if Decimal.equal?(decimal, 0) do
      "0"
    else
      decimal
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
    end
  end

  defp value(:text, value), do: value
  defp value(:integer, value), do: Integer.to_string(value)
  defp value(:decimal, value), do: canonical_decimal(value)
  defp value(:boolean, true), do: <<1>>
  defp value(:boolean, false), do: <<0>>

  defp value(:utc_datetime, value) do
    value
    |> DateTime.to_unix(:microsecond)
    |> Integer.to_string()
  end

  defp value(:asset, value), do: uuid_bytes!(value)

  defp uuid_bytes!(uuid) do
    {:ok, bytes} = Ecto.UUID.dump(uuid)
    bytes
  end

  defp frame(value) do
    bytes = IO.iodata_to_binary(value)
    [<<byte_size(bytes)::unsigned-big-32>>, bytes]
  end
end
