defmodule QuickTrain.Datasets.DatasetValue.TypedChildConstraint do
  @moduledoc false

  @tables ~w(
    dataset_values
    dataset_text_values
    dataset_integer_values
    dataset_decimal_values
    dataset_boolean_values
    dataset_date_time_values
    dataset_asset_values
  )

  def tables, do: @tables

  def validate_function do
    """
    CREATE FUNCTION quick_train_validate_dataset_value(p_value_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_family text;
      v_text_count bigint;
      v_integer_count bigint;
      v_decimal_count bigint;
      v_boolean_count bigint;
      v_date_time_count bigint;
      v_asset_count bigint;
      v_total bigint;
      v_compatible boolean;
    BEGIN
      SELECT field_definition.value_family
      INTO v_family
      FROM dataset_values AS dataset_value
      JOIN dataset_field_definitions AS field_definition
        ON field_definition.id = dataset_value.field_definition_id
      WHERE dataset_value.id = p_value_id;

      IF v_family IS NULL THEN
        RETURN;
      END IF;

      SELECT
        (SELECT count(*) FROM dataset_text_values WHERE dataset_value_id = p_value_id),
        (SELECT count(*) FROM dataset_integer_values WHERE dataset_value_id = p_value_id),
        (SELECT count(*) FROM dataset_decimal_values WHERE dataset_value_id = p_value_id),
        (SELECT count(*) FROM dataset_boolean_values WHERE dataset_value_id = p_value_id),
        (SELECT count(*) FROM dataset_date_time_values WHERE dataset_value_id = p_value_id),
        (SELECT count(*) FROM dataset_asset_values WHERE dataset_value_id = p_value_id)
      INTO
        v_text_count,
        v_integer_count,
        v_decimal_count,
        v_boolean_count,
        v_date_time_count,
        v_asset_count;

      v_total :=
        v_text_count + v_integer_count + v_decimal_count +
        v_boolean_count + v_date_time_count + v_asset_count;

      v_compatible := CASE v_family
        WHEN 'text' THEN v_text_count = 1
        WHEN 'integer' THEN v_integer_count = 1
        WHEN 'decimal' THEN v_decimal_count = 1
        WHEN 'boolean' THEN v_boolean_count = 1
        WHEN 'utc_datetime' THEN v_date_time_count = 1
        WHEN 'asset' THEN v_asset_count = 1
        ELSE false
      END;

      IF v_total <> 1 OR NOT v_compatible THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'dataset value must have exactly one compatible typed child',
          CONSTRAINT = 'dataset_values_exactly_one_typed_child',
          TABLE = 'dataset_values';
      END IF;
    END;
    $$;
    """
  end

  def enforce_function do
    """
    CREATE FUNCTION quick_train_enforce_dataset_value_typed_child()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_previous_id uuid;
      v_current_id uuid;
    BEGIN
      IF TG_TABLE_NAME = 'dataset_values' THEN
        IF TG_OP <> 'INSERT' THEN
          v_previous_id := OLD.id;
        END IF;

        IF TG_OP <> 'DELETE' THEN
          v_current_id := NEW.id;
        END IF;
      ELSE
        IF TG_OP <> 'INSERT' THEN
          v_previous_id := OLD.dataset_value_id;
        END IF;

        IF TG_OP <> 'DELETE' THEN
          v_current_id := NEW.dataset_value_id;
        END IF;
      END IF;

      IF v_previous_id IS NOT NULL AND v_previous_id IS DISTINCT FROM v_current_id THEN
        PERFORM quick_train_validate_dataset_value(v_previous_id);
      END IF;

      IF v_current_id IS NOT NULL THEN
        PERFORM quick_train_validate_dataset_value(v_current_id);
      END IF;

      IF TG_OP = 'DELETE' THEN
        RETURN OLD;
      END IF;

      RETURN NEW;
    END;
    $$;
    """
  end

  def trigger(table) when table in @tables do
    """
    CREATE CONSTRAINT TRIGGER #{table}_typed_child_constraint
    AFTER INSERT OR UPDATE OR DELETE ON #{table}
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION quick_train_enforce_dataset_value_typed_child();
    """
  end

  def drop_trigger(table) when table in @tables do
    "DROP TRIGGER IF EXISTS #{table}_typed_child_constraint ON #{table};"
  end
end
