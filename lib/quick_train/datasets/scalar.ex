defmodule QuickTrain.Datasets.Scalar do
  @moduledoc false

  def cast(:text, value) when is_binary(value) do
    if String.valid?(value) and not String.contains?(value, <<0>>),
      do: Ash.Type.cast_input(:string, value, trim?: false, allow_empty?: true),
      else: :error
  end

  def cast(:integer, value)
      when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
      do: Ash.Type.cast_input(:integer, value)

  def cast(:decimal, value) when is_binary(value) or is_struct(value, Decimal) do
    # Keep Decimal's bounds for structs and reject special values before Ash's struct cast.
    with {:ok, decimal} <- Decimal.cast(value),
         false <- Decimal.nan?(decimal) or Decimal.inf?(decimal),
         {:ok, decimal} <- Ash.Type.cast_input(:decimal, decimal) do
      {:ok, decimal}
    else
      _invalid -> :error
    end
  end

  def cast(:boolean, value) when is_boolean(value), do: {:ok, value}

  def cast(:utc_datetime, %DateTime{} = value),
    do: {:ok, DateTime.shift_zone!(value, "Etc/UTC")}

  def cast(:utc_datetime, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> {:ok, date_time}
      _invalid -> :error
    end
  end

  def cast(:asset, value) when is_binary(value), do: Ash.Type.cast_input(:uuid, value)
  def cast(_family, _value), do: :error
end
