defmodule QuickTrain.Datasets.DatasetRecord.Values do
  @moduledoc false

  require Ash.Query

  alias QuickTrain.Assets.Asset
  alias QuickTrain.Datasets.DatasetValue.Family

  @families Family.values()
  @typed_relationships [
    :text_value,
    :integer_value,
    :decimal_value,
    :boolean_value,
    :date_time_value,
    :asset_value
  ]

  def normalize(schema, values) when is_list(values) do
    fields = Map.new(schema.root_record_type.field_definitions, &{&1.key, &1})

    with {:ok, occurrences} <- normalize_entries(values, fields),
         :ok <- required_fields_present(fields, occurrences) do
      {:ok, occurrences}
    end
  end

  def normalize(_schema, _values), do: {:error, :unsupported_structure}

  defp normalize_entries(values, fields) do
    Enum.reduce_while(values, {:ok, [], MapSet.new()}, fn value, {:ok, entries, seen} ->
      with {:ok, field_key} <- fetch_field(value),
           %{} = field <- Map.get(fields, field_key),
           false <- MapSet.member?(seen, field.id),
           {:ok, family, normalized} <- normalize_typed_value(value),
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
    if String.valid?(value), do: {:ok, :text, value}, else: {:error, :type_mismatch}
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
        ready_ids =
          Asset
          |> Ash.Query.filter(
            id in ^ids and organization_id == ^organization_id and state == :ready
          )
          |> Ash.Query.select([:id])
          |> Ash.read!(authorize?: false)
          |> MapSet.new(& &1.id)

        if MapSet.equal?(ready_ids, MapSet.new(ids)), do: :ok, else: {:error, :invalid_asset}
    end
  end

  def load(record) do
    record =
      Ash.load!(record, [values: [:field_definition | @typed_relationships]], authorize?: false)

    Enum.map(record.values, fn value ->
      family = value.field_definition.value_family

      %{
        field: value.field_definition,
        family: family,
        ordinal: value.ordinal,
        value: typed_value(value, family)
      }
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
