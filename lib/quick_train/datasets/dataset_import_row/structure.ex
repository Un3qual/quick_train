defmodule QuickTrain.Datasets.DatasetImportRow.Structure do
  # Structural rejection order is intentionally represented in one reduce_while boundary.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  alias QuickTrain.Datasets.{Fingerprint, Scalar}

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

    cond do
      byte_size(arguments.row_key) == 0 or not valid_identifier?(arguments.row_key) ->
        {:error, :invalid_row_key}

      not valid_identifier?(arguments.external_key) ->
        {:error, :invalid_external_key}

      arguments.source_position < 0 ->
        {:error, :invalid_source_position}

      length(arguments.values) > limits[:max_fields_per_row] ->
        {:error, :row_field_limit_exceeded}

      true ->
        values = Enum.map(arguments.values, &plain_map/1)

        if :erlang.external_size({arguments.row_key, arguments.external_key, values}) >
             limits[:max_request_bytes] do
          {:error, :request_limit_exceeded}
        else
          normalize(values, limits)
        end
    end
  end

  defp valid_identifier?(nil), do: true

  defp valid_identifier?(value),
    do: String.valid?(value) and not String.contains?(value, <<0>>)

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

  defp normalize_value(selector, value) do
    # Imports accept wire representations; direct revisions may also accept typed structs.
    family = Keyword.fetch!(@selectors, selector)

    if selector in [:decimal, :utc_datetime] and not is_binary(value) do
      {:error, :malformed_scalar_shape}
    else
      case Scalar.cast(family, value) do
        {:ok, normalized} -> {:ok, normalized, scalar_bytes(family, normalized)}
        _invalid -> {:error, scalar_error(selector, value)}
      end
    end
  end

  defp scalar_bytes(:text, value), do: byte_size(value)
  defp scalar_bytes(:integer, value), do: byte_size(Integer.to_string(value))
  defp scalar_bytes(:decimal, value), do: byte_size(Fingerprint.canonical_decimal(value))
  defp scalar_bytes(:boolean, _value), do: 1

  defp scalar_bytes(:utc_datetime, value),
    do: byte_size(Integer.to_string(DateTime.to_unix(value, :microsecond)))

  defp scalar_bytes(:asset, _value), do: 16

  defp scalar_error(:text, value) when is_binary(value), do: :malformed_text
  defp scalar_error(:decimal, value) when is_binary(value), do: :malformed_decimal
  defp scalar_error(:utc_datetime, value) when is_binary(value), do: :malformed_utc_datetime
  defp scalar_error(:asset_id, value) when is_binary(value), do: :malformed_asset_id
  defp scalar_error(_selector, _value), do: :malformed_scalar_shape

  defp plain_map(%_{} = value), do: Map.from_struct(value)
  defp plain_map(value) when is_map(value), do: value
end
