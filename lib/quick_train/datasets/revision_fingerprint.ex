defmodule QuickTrain.Datasets.RevisionFingerprint do
  @moduledoc false

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

  defp occurrence_bytes(occurrence) do
    frame([
      frame(uuid_bytes!(occurrence.field.id)),
      frame(Atom.to_string(occurrence.family)),
      frame(Integer.to_string(occurrence.ordinal)),
      frame(typed_bytes(occurrence.family, occurrence.value))
    ])
  end

  defp typed_bytes(:text, value), do: value
  defp typed_bytes(:integer, value), do: Integer.to_string(value)
  defp typed_bytes(:decimal, value), do: canonical_decimal(value)
  defp typed_bytes(:boolean, true), do: <<1>>
  defp typed_bytes(:boolean, false), do: <<0>>

  defp typed_bytes(:utc_datetime, value) do
    value
    |> DateTime.to_unix(:microsecond)
    |> Integer.to_string()
  end

  defp typed_bytes(:asset, value), do: uuid_bytes!(value)

  defp uuid_bytes!(uuid) do
    {:ok, bytes} = Ecto.UUID.dump(uuid)
    bytes
  end

  defp frame(value) do
    bytes = IO.iodata_to_binary(value)
    [<<byte_size(bytes)::unsigned-big-32>>, bytes]
  end
end
