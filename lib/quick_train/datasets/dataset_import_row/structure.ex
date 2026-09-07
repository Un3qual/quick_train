defmodule QuickTrain.Datasets.DatasetImportRow.Structure do
  # Structural rejection order is intentionally represented in one reduce_while boundary.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  alias QuickTrain.Datasets.FingerprintEncoding

  @selectors [
    text: :text,
    integer: :integer,
    decimal: :decimal,
    boolean: :boolean,
    utc_datetime: :utc_datetime,
    asset_id: :asset
  ]

  def validate(arguments) do
    limits = Application.fetch_env!(:quick_train, :dataset_imports)
    values = Enum.map(arguments.values, &plain_map/1)

    cond do
      byte_size(arguments.row_key) == 0 ->
        {:error, :invalid_row_key}

      arguments.source_position < 0 ->
        {:error, :invalid_source_position}

      length(values) > limits[:max_fields_per_row] ->
        {:error, :row_field_limit_exceeded}

      :erlang.external_size({arguments.row_key, arguments.external_key, values}) >
          limits[:max_request_bytes] ->
        {:error, :request_limit_exceeded}

      true ->
        normalize(values, limits)
    end
  end

  defp normalize(values, limits) do
    Enum.reduce_while(values, {:ok, [], 0}, fn value, {:ok, entries, total_bytes} ->
      with field when is_binary(field) and field != "" <- Map.get(value, :field),
           [{selector, family}] <-
             Enum.filter(@selectors, fn {selector, _family} ->
               not is_nil(Map.get(value, selector))
             end),
           {:ok, normalized, bytes} <- normalize_value(selector, Map.fetch!(value, selector)),
           true <- bytes <= limits[:max_text_bytes] or selector != :text,
           next_bytes = total_bytes + byte_size(field) + bytes,
           true <- next_bytes <= limits[:max_scalar_bytes_per_row] do
        entry = %{field: field, family: family, value: normalized}
        {:cont, {:ok, [entry | entries], next_bytes}}
      else
        [] -> {:halt, {:error, :malformed_scalar_shape}}
        [_one, _two | _rest] -> {:halt, {:error, :malformed_scalar_shape}}
        false -> {:halt, {:error, :row_scalar_limit_exceeded}}
        {:error, reason} -> {:halt, {:error, reason}}
        _other -> {:halt, {:error, :malformed_scalar_shape}}
      end
    end)
    |> case do
      {:ok, entries, _bytes} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp normalize_value(:text, value) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value, byte_size(value)},
      else: {:error, :malformed_text}
  end

  defp normalize_value(:integer, value) when is_integer(value) do
    {:ok, value, byte_size(Integer.to_string(value))}
  end

  defp normalize_value(:decimal, value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} ->
        canonical = FingerprintEncoding.canonical_decimal(decimal)
        {:ok, decimal, byte_size(canonical)}

      _other ->
        {:error, :malformed_decimal}
    end
  end

  defp normalize_value(:boolean, value) when is_boolean(value), do: {:ok, value, 1}

  defp normalize_value(:utc_datetime, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} ->
        {:ok, date_time, byte_size(Integer.to_string(DateTime.to_unix(date_time, :microsecond)))}

      _other ->
        {:error, :malformed_utc_datetime}
    end
  end

  defp normalize_value(:asset_id, value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, asset_id} -> {:ok, asset_id, 16}
      :error -> {:error, :malformed_asset_id}
    end
  end

  defp normalize_value(_selector, _value), do: {:error, :malformed_scalar_shape}

  defp plain_map(%_{} = value), do: Map.from_struct(value)
  defp plain_map(value) when is_map(value), do: value
end
