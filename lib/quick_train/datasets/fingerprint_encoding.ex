defmodule QuickTrain.Datasets.FingerprintEncoding do
  @moduledoc false

  def digest(payload) do
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

  def value(:text, value), do: value
  def value(:integer, value), do: Integer.to_string(value)
  def value(:decimal, value), do: canonical_decimal(value)
  def value(:boolean, true), do: <<1>>
  def value(:boolean, false), do: <<0>>

  def value(:utc_datetime, value) do
    value
    |> DateTime.to_unix(:microsecond)
    |> Integer.to_string()
  end

  def value(:asset, value), do: uuid_bytes!(value)

  def uuid_bytes!(uuid) do
    {:ok, bytes} = Ecto.UUID.dump(uuid)
    bytes
  end

  def frame(value) do
    bytes = IO.iodata_to_binary(value)
    [<<byte_size(bytes)::unsigned-big-32>>, bytes]
  end
end
