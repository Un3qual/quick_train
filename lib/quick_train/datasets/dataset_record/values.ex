defmodule QuickTrain.Datasets.DatasetRecord.Values do
  @moduledoc false

  alias QuickTrain.Assets.Asset
  alias QuickTrain.Datasets.DatasetValue.Family

  @families Family.values()
  @typed_relationships [
    text: :text_value,
    integer: :integer_value,
    decimal: :decimal_value,
    boolean: :boolean_value,
    utc_datetime: :date_time_value,
    asset: :asset_value
  ]

  def normalize(schema, values) when is_list(values),
    do: resolve(schema, values, &normalize_typed_value/1)

  def normalize(_schema, _values), do: {:error, :unsupported_structure}

  def bind(schema, entries) do
    resolve(schema, entries, fn %{family: family, value: value} -> {:ok, family, value} end)
  end

  defp resolve(schema, values, value_parser) do
    fields = Map.new(schema.root_record_type.field_definitions, &{&1.key, &1})

    with {:ok, occurrences} <- normalize_entries(values, fields, value_parser),
         :ok <- required_fields_present(fields, occurrences) do
      {:ok, occurrences}
    end
  end

  defp normalize_entries(values, fields, value_parser) do
    Enum.reduce_while(values, {:ok, [], MapSet.new()}, fn value, {:ok, entries, seen} ->
      with {:ok, field_key} <- fetch_field(value),
           %{} = field <- Map.get(fields, field_key),
           false <- MapSet.member?(seen, field.id),
           {:ok, family, normalized} <- value_parser.(value),
           true <- family == field.value_family do
        occurrence = %{field: field, family: family, ordinal: 0, value: normalized}
        {:cont, {:ok, [occurrence | entries], MapSet.put(seen, field.id)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        nil -> {:halt, {:error, :unknown_field}}
        true -> {:halt, {:error, :repeated_single}}
        false -> {:halt, {:error, :type_mismatch}}
      end
    end)
    |> case do
      {:ok, entries, _seen} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp fetch_field(value) when is_map(value) do
    case fetch(value, :field) do
      field when is_binary(field) and field != "" -> {:ok, field}
      _other -> {:error, :unknown_field}
    end
  end

  defp fetch_field(_value), do: {:error, :unsupported_structure}

  defp normalize_typed_value(value) do
    if present?(value, :record) do
      {:error, :unsupported_structure}
    else
      present = Enum.filter(@families, &present?(value, selector(&1)))

      case present do
        [family] -> normalize_family(family, fetch(value, selector(family)))
        _other -> {:error, :type_mismatch}
      end
    end
  end

  defp normalize_family(:text, value) when is_binary(value) do
    if String.valid?(value) and not String.contains?(value, <<0>>),
      do: {:ok, :text, value},
      else: {:error, :type_mismatch}
  end

  defp normalize_family(:integer, value) when is_integer(value), do: {:ok, :integer, value}

  defp normalize_family(:decimal, %Decimal{} = value), do: {:ok, :decimal, value}

  defp normalize_family(:decimal, value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} -> {:ok, :decimal, decimal}
      _other -> {:error, :type_mismatch}
    end
  end

  defp normalize_family(:boolean, value) when is_boolean(value), do: {:ok, :boolean, value}

  defp normalize_family(:utc_datetime, %DateTime{} = value),
    do: {:ok, :utc_datetime, DateTime.shift_zone!(value, "Etc/UTC")}

  defp normalize_family(:utc_datetime, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> {:ok, :utc_datetime, date_time}
      _other -> {:error, :type_mismatch}
    end
  end

  defp normalize_family(:asset, value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, asset_id} -> {:ok, :asset, asset_id}
      :error -> {:error, :type_mismatch}
    end
  end

  defp normalize_family(_family, _value), do: {:error, :type_mismatch}

  defp required_fields_present(fields, occurrences) do
    present = MapSet.new(occurrences, & &1.field.id)

    missing =
      fields
      |> Enum.filter(fn {_key, field} ->
        field.required and not MapSet.member?(present, field.id)
      end)
      |> Enum.map_join(",", fn {key, _field} -> key end)

    case missing do
      "" -> :ok
      keys -> {:error, "required_missing:#{keys}"}
    end
  end

  def validate_assets(organization_id, occurrences) do
    ids =
      occurrences |> Enum.filter(&(&1.family == :asset)) |> Enum.map(& &1.value) |> Enum.uniq()

    case ids do
      [] ->
        :ok

      ids ->
        ready_count =
          Ash.count!(Asset,
            query: [filter: [id: [in: ids], organization_id: organization_id, state: :ready]],
            authorize?: false
          )

        if ready_count == length(ids), do: :ok, else: {:error, :invalid_asset}
    end
  end

  def load(record, schema) do
    fields = Map.new(schema.root_record_type.field_definitions, &{&1.id, &1})
    record = Ash.load!(record, :values, authorize?: false)

    record.values
    |> Enum.group_by(&Map.fetch!(fields, &1.field_definition_id).value_family)
    |> Enum.flat_map(fn {family, values} ->
      values
      |> Ash.load!(Keyword.fetch!(@typed_relationships, family), authorize?: false)
      |> Enum.map(fn value ->
        %{
          field: Map.fetch!(fields, value.field_definition_id),
          family: family,
          ordinal: value.ordinal,
          value: typed_value(value, family)
        }
      end)
    end)
  end

  defp typed_value(value, :text), do: value.text_value.value
  defp typed_value(value, :integer), do: value.integer_value.value
  defp typed_value(value, :decimal), do: value.decimal_value.value
  defp typed_value(value, :boolean), do: value.boolean_value.value
  defp typed_value(value, :utc_datetime), do: value.date_time_value.value
  defp typed_value(value, :asset), do: value.asset_value.asset_id

  defp selector(:utc_datetime), do: :utc_datetime
  defp selector(:asset), do: :asset_id
  defp selector(family), do: family

  defp present?(map, key), do: not is_nil(fetch(map, key))

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
