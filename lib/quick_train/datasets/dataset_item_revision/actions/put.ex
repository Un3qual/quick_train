defmodule QuickTrain.Datasets.DatasetItemRevision.Actions.Put do
  # The nested branch is the item-lock transaction's explicit rollback state machine.
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias QuickTrain.AshError
  alias QuickTrain.Assets.Asset

  alias QuickTrain.Datasets.{
    DatasetAssetValue,
    DatasetBooleanValue,
    DatasetDateTimeValue,
    DatasetDecimalValue,
    DatasetIntegerValue,
    DatasetItem,
    DatasetItemRevision,
    DatasetRecord,
    DatasetRevisionResult,
    DatasetSchemaVersion,
    DatasetTextValue,
    DatasetValue,
    RevisionFingerprint
  }

  @families QuickTrain.Datasets.DatasetValueFamily.values()
  @item_conflicts ["dataset_items_pkey", "dataset_items_dataset_external_key_index"]
  @attempts 2

  @impl true
  def run(input, _opts, _context) do
    arguments = input.arguments

    with %{} = schema <- published_schema(arguments),
         {:ok, occurrences} <- normalize(schema, arguments.values),
         fingerprint <-
           RevisionFingerprint.encode(schema.id, schema.root_record_type_id, occurrences) do
      put(arguments, schema, occurrences, fingerprint, @attempts)
    else
      nil -> {:error, :invalid_schema}
      {:error, reason} -> {:error, reason}
    end
  end

  defp published_schema(arguments) do
    DatasetSchemaVersion
    |> Ash.Query.filter(
      id == ^arguments.schema_version_id and
        dataset_id == ^arguments.dataset_id and
        dataset.organization_id == ^arguments.organization_id and
        state == :published
    )
    |> Ash.Query.load(root_record_type: :field_definitions)
    |> Ash.read_one!(authorize?: false)
  end

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

  defp put(arguments, schema, occurrences, fingerprint, attempts) do
    resources = [
      DatasetItem,
      DatasetItemRevision,
      DatasetRecord,
      DatasetValue,
      DatasetTextValue,
      DatasetIntegerValue,
      DatasetDecimalValue,
      DatasetBooleanValue,
      DatasetDateTimeValue,
      DatasetAssetValue,
      Asset
    ]

    result =
      Ash.transact(resources, fn ->
        with {:ok, item} <- stable_item(arguments),
             %{} = item <- locked_item(arguments, item.id),
             :ok <- matching_identity(item, arguments),
             :ok <- validate_assets(arguments.organization_id, occurrences) do
          latest = latest_revision(item.id)

          if latest && latest.fingerprint == fingerprint do
            %DatasetRevisionResult{changed: false, item: item, revision: latest}
          else
            revision = create_revision!(arguments, schema, item, latest, occurrences, fingerprint)
            %DatasetRevisionResult{changed: true, item: item, revision: revision}
          end
        else
          nil -> {:error, :invalid_item}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, %DatasetRevisionResult{} = revision_result} ->
        {:ok, revision_result}

      {:error, error} when attempts > 1 ->
        if AshError.constraint?(error, @item_conflicts) do
          put(arguments, schema, occurrences, fingerprint, attempts - 1)
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp stable_item(arguments) do
    case existing_item(arguments) do
      nil -> create_item(arguments)
      item -> {:ok, item}
    end
  end

  defp existing_item(%{item_id: item_id} = arguments) when not is_nil(item_id) do
    DatasetItem
    |> Ash.Query.filter(
      id == ^item_id and dataset_id == ^arguments.dataset_id and
        organization_id == ^arguments.organization_id
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp existing_item(arguments) do
    DatasetItem
    |> Ash.Query.filter(
      dataset_id == ^arguments.dataset_id and organization_id == ^arguments.organization_id and
        external_key == ^arguments.external_key
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp create_item(arguments) do
    attributes = %{
      organization_id: arguments.organization_id,
      dataset_id: arguments.dataset_id,
      external_key: arguments.external_key
    }

    attributes =
      if arguments.item_id, do: Map.put(attributes, :id, arguments.item_id), else: attributes

    DatasetItem
    |> Ash.Changeset.for_create(:create_internal, attributes)
    |> Ash.create(authorize?: false)
  end

  defp locked_item(arguments, item_id) do
    DatasetItem
    |> Ash.Query.filter(
      id == ^item_id and dataset_id == ^arguments.dataset_id and
        organization_id == ^arguments.organization_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp matching_identity(item, %{external_key: nil}),
    do: if(item.external_key, do: {:error, :item_identity_conflict}, else: :ok)

  defp matching_identity(item, arguments) do
    if item.external_key == arguments.external_key,
      do: :ok,
      else: {:error, :item_identity_conflict}
  end

  def validate_assets(organization_id, occurrences) do
    occurrences
    |> Enum.filter(&(&1.family == :asset))
    |> Enum.reduce_while(:ok, fn occurrence, :ok ->
      asset =
        Asset
        |> Ash.Query.filter(
          id == ^occurrence.value and organization_id == ^organization_id and state == :ready
        )
        |> Ash.read_one!(authorize?: false)

      if asset, do: {:cont, :ok}, else: {:halt, {:error, :invalid_asset}}
    end)
  end

  defp latest_revision(item_id) do
    DatasetItemRevision
    |> Ash.Query.filter(item_id == ^item_id)
    |> Ash.Query.sort(revision_number: :desc, id: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp create_revision!(arguments, schema, item, latest, occurrences, fingerprint) do
    record = create_normalized_record!(arguments, schema, occurrences)

    DatasetItemRevision
    |> Ash.Changeset.for_create(:create_internal, %{
      organization_id: arguments.organization_id,
      dataset_id: arguments.dataset_id,
      item_id: item.id,
      schema_version_id: schema.id,
      root_record_type_id: schema.root_record_type_id,
      root_record_id: record.id,
      revision_number: if(latest, do: latest.revision_number + 1, else: 1),
      fingerprint: fingerprint
    })
    |> Ash.create!(authorize?: false)
  end

  def create_normalized_record!(scope, schema, occurrences) do
    record =
      DatasetRecord
      |> Ash.Changeset.for_create(:create_internal, %{
        organization_id: scope.organization_id,
        dataset_id: scope.dataset_id,
        schema_version_id: schema.id,
        record_type_id: schema.root_record_type_id
      })
      |> Ash.create!(authorize?: false)

    Enum.each(occurrences, &create_occurrence!(scope, schema, record, &1))
    record
  end

  defp create_occurrence!(arguments, schema, record, occurrence) do
    value =
      DatasetValue
      |> Ash.Changeset.for_create(:create_internal, %{
        organization_id: arguments.organization_id,
        dataset_id: arguments.dataset_id,
        schema_version_id: schema.id,
        record_type_id: schema.root_record_type_id,
        record_id: record.id,
        field_definition_id: occurrence.field.id,
        ordinal: occurrence.ordinal
      })
      |> Ash.create!(authorize?: false)

    create_typed_value!(value.id, arguments.organization_id, occurrence)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :text, value: value}) do
    create_scalar!(DatasetTextValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :integer, value: value}) do
    create_scalar!(DatasetIntegerValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :decimal, value: value}) do
    create_scalar!(DatasetDecimalValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{family: :boolean, value: value}) do
    create_scalar!(DatasetBooleanValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, _organization_id, %{
         family: :utc_datetime,
         value: value
       }) do
    create_scalar!(DatasetDateTimeValue, dataset_value_id, value)
  end

  defp create_typed_value!(dataset_value_id, organization_id, %{family: :asset, value: asset_id}) do
    DatasetAssetValue
    |> Ash.Changeset.for_create(:create_internal, %{
      dataset_value_id: dataset_value_id,
      organization_id: organization_id,
      asset_id: asset_id
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_scalar!(resource, dataset_value_id, value) do
    resource
    |> Ash.Changeset.for_create(:create_internal, %{
      dataset_value_id: dataset_value_id,
      value: value
    })
    |> Ash.create!(authorize?: false)
  end

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
