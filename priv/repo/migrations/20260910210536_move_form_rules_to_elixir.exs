defmodule QuickTrain.Repo.Migrations.MoveFormRulesToElixir do
  @moduledoc """
  Removes Forms lifecycle and subtype triggers; Ash authoring actions own these rules.
  Retains the existing deferred position constraints on their respective resources.

  Generated with `mix ash_postgres.generate_migrations`, then simplified to leave
  unchanged position constraints and their indexes in place in both directions.
  """

  use Ecto.Migration

  def up do
    execute("""
    DO $forms_migration$ BEGIN
    EXECUTE $forms_ddl$DROP TRIGGER forms_owner_guard ON forms;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_versions_owner_guard ON form_versions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_input_slot_definitions_draft_guard ON form_input_slot_definitions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_input_field_requirements_draft_guard ON form_input_field_requirements;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_definitions_draft_guard ON form_question_definitions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_text_constraints_draft_guard ON form_text_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_integer_constraints_draft_guard ON form_integer_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_decimal_constraints_draft_guard ON form_decimal_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_selection_constraints_draft_guard ON form_selection_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_annotation_constraints_draft_guard ON form_annotation_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_input_sources_draft_guard ON form_input_sources;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_options_draft_guard ON form_question_options;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_label_sets_draft_guard ON form_label_sets;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_labels_draft_guard ON form_labels;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_presentation_elements_draft_guard ON form_presentation_elements;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_instructions_draft_guard ON form_instructions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_headings_draft_guard ON form_headings;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_sections_draft_guard ON form_sections;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_bound_values_draft_guard ON form_bound_values;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_placements_draft_guard ON form_question_placements;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_presentation_elements_typed_guard ON form_presentation_elements;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_instructions_typed_guard ON form_instructions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_headings_typed_guard ON form_headings;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_sections_typed_guard ON form_sections;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_bound_values_typed_guard ON form_bound_values;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_placements_typed_guard ON form_question_placements;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_definitions_typed_guard ON form_question_definitions;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_text_constraints_typed_guard ON form_text_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_integer_constraints_typed_guard ON form_integer_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_decimal_constraints_typed_guard ON form_decimal_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_selection_constraints_typed_guard ON form_selection_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_annotation_constraints_typed_guard ON form_annotation_constraints;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_input_sources_typed_guard ON form_input_sources;$forms_ddl$;
    EXECUTE $forms_ddl$DROP TRIGGER form_question_options_typed_guard ON form_question_options;$forms_ddl$;
    EXECUTE $forms_ddl$DROP FUNCTION quick_train_form_typed_trigger();$forms_ddl$;
    EXECUTE $forms_ddl$DROP FUNCTION quick_train_check_form_question(uuid);$forms_ddl$;
    EXECUTE $forms_ddl$DROP FUNCTION quick_train_check_form_presentation(uuid);$forms_ddl$;
    EXECUTE $forms_ddl$DROP FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$DROP FUNCTION quick_train_form_owner_guard();$forms_ddl$;
    END $forms_migration$;
    """)
  end

  def down do
    execute("""
    DO $forms_migration$ BEGIN
    EXECUTE $forms_ddl$CREATE FUNCTION quick_train_form_owner_guard() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_TABLE_NAME = 'forms' THEN
        IF TG_OP = 'UPDATE' AND (NEW.id, NEW.organization_id, NEW.key) IS DISTINCT FROM (OLD.id, OLD.organization_id, OLD.key) THEN
          RAISE EXCEPTION 'immutable form identity' USING ERRCODE = '23514';
        END IF;
      ELSE
        IF TG_OP = 'INSERT' THEN
          IF NEW.state <> 'draft' OR NEW.published_at IS NOT NULL THEN
            RAISE EXCEPTION 'new form versions must be drafts' USING ERRCODE = '23514';
          END IF;
        ELSE
          IF OLD.state = 'published' THEN
            RAISE EXCEPTION 'published form version is immutable' USING ERRCODE = '23514';
          END IF;
          IF TG_OP = 'UPDATE' AND (NEW.id, NEW.form_id, NEW.version) IS DISTINCT FROM (OLD.id, OLD.form_id, OLD.version) THEN
            RAISE EXCEPTION 'immutable form version identity' USING ERRCODE = '23514';
          END IF;
        END IF;
      END IF;
      IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
      RETURN NEW;
    END; $$;
    $forms_ddl$;
    EXECUTE $forms_ddl$CREATE FUNCTION quick_train_form_child_guard() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE owner_id uuid; owner_state text;
    BEGIN
      IF TG_OP = 'INSERT' THEN owner_id := NEW.version_id; ELSE owner_id := OLD.version_id; END IF;
      SELECT state INTO owner_state FROM form_versions WHERE id = owner_id FOR UPDATE;
      IF owner_state IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'form version must be a draft' USING ERRCODE = '23514';
      END IF;
      IF TG_OP = 'UPDATE' THEN
        IF (OLD.id, OLD.version_id) IS DISTINCT FROM (NEW.id, NEW.version_id) THEN
          RAISE EXCEPTION 'immutable definition ownership' USING ERRCODE = '23514';
        END IF;
        IF TG_TABLE_NAME IN ('form_input_slot_definitions','form_input_field_requirements','form_question_definitions','form_question_options','form_label_sets','form_labels') THEN
          IF OLD.key IS DISTINCT FROM NEW.key THEN RAISE EXCEPTION 'immutable definition key' USING ERRCODE = '23514'; END IF;
        END IF;
        IF TG_TABLE_NAME = 'form_input_field_requirements' THEN
          IF OLD.input_slot_id IS DISTINCT FROM NEW.input_slot_id THEN RAISE EXCEPTION 'immutable input slot ownership' USING ERRCODE = '23514'; END IF;
        ELSIF TG_TABLE_NAME = 'form_labels' THEN
          IF OLD.label_set_id IS DISTINCT FROM NEW.label_set_id THEN RAISE EXCEPTION 'immutable label ownership' USING ERRCODE = '23514'; END IF;
        ELSIF TG_TABLE_NAME IN ('form_text_constraints','form_integer_constraints','form_decimal_constraints','form_selection_constraints','form_annotation_constraints','form_input_sources','form_question_options') THEN
          IF OLD.question_id IS DISTINCT FROM NEW.question_id THEN RAISE EXCEPTION 'immutable question ownership' USING ERRCODE = '23514'; END IF;
        ELSIF TG_TABLE_NAME IN ('form_instructions','form_headings','form_sections','form_bound_values','form_question_placements') THEN
          IF OLD.element_id IS DISTINCT FROM NEW.element_id THEN RAISE EXCEPTION 'immutable element ownership' USING ERRCODE = '23514'; END IF;
        ELSIF TG_TABLE_NAME = 'form_presentation_elements' THEN
          IF OLD.kind IS DISTINCT FROM NEW.kind THEN RAISE EXCEPTION 'immutable element kind' USING ERRCODE = '23514'; END IF;
        END IF;
      END IF;
      IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
      RETURN NEW;
    END; $$;
    $forms_ddl$;
    EXECUTE $forms_ddl$CREATE FUNCTION quick_train_check_form_presentation(element_uuid uuid) RETURNS void LANGUAGE plpgsql AS $$
    DECLARE element_kind text; matching bigint; total bigint;
    BEGIN
      SELECT kind INTO element_kind FROM form_presentation_elements WHERE id = element_uuid;
      IF NOT FOUND THEN RETURN; END IF;
      SELECT count(*), count(*) FILTER (WHERE kind = element_kind) INTO total, matching FROM (
        SELECT 'instruction' AS kind FROM form_instructions WHERE element_id = element_uuid
        UNION ALL SELECT 'heading' FROM form_headings WHERE element_id = element_uuid
        UNION ALL SELECT 'section' FROM form_sections WHERE element_id = element_uuid
        UNION ALL SELECT 'bound_value' FROM form_bound_values WHERE element_id = element_uuid
        UNION ALL SELECT 'question' FROM form_question_placements WHERE element_id = element_uuid
      ) children;
      IF total <> 1 OR matching <> 1 THEN
        RAISE EXCEPTION 'presentation requires one matching subtype' USING ERRCODE = '23514';
      END IF;
    END; $$;
    $forms_ddl$;
    EXECUTE $forms_ddl$CREATE FUNCTION quick_train_check_form_question(question_uuid uuid) RETURNS void LANGUAGE plpgsql AS $$
    DECLARE answer_family text; invalid boolean;
    BEGIN
      SELECT family INTO answer_family FROM form_question_definitions WHERE id = question_uuid;
      IF NOT FOUND THEN RETURN; END IF;
      SELECT EXISTS (
        SELECT 1 FROM form_text_constraints WHERE question_id = question_uuid AND answer_family <> 'text'
        UNION ALL SELECT 1 FROM form_integer_constraints WHERE question_id = question_uuid AND answer_family <> 'integer'
        UNION ALL SELECT 1 FROM form_decimal_constraints WHERE question_id = question_uuid AND answer_family <> 'decimal'
        UNION ALL SELECT 1 FROM form_selection_constraints WHERE question_id = question_uuid AND answer_family NOT IN ('static_single_choice','static_multiple_choice','task_input_single_choice','task_input_multiple_choice')
        UNION ALL SELECT 1 FROM form_annotation_constraints WHERE question_id = question_uuid AND answer_family NOT IN ('bounding_boxes','polygon_regions','raster_masks','text_spans')
        UNION ALL SELECT 1 FROM form_input_sources WHERE question_id = question_uuid AND answer_family NOT IN ('task_input_single_choice','task_input_multiple_choice','task_input_ranking')
        UNION ALL SELECT 1 FROM form_question_options WHERE question_id = question_uuid AND answer_family NOT IN ('static_single_choice','static_multiple_choice')
      ) INTO invalid;
      IF invalid THEN RAISE EXCEPTION 'incompatible question subtype' USING ERRCODE = '23514'; END IF;
    END; $$;
    $forms_ddl$;
    EXECUTE $forms_ddl$CREATE FUNCTION quick_train_form_typed_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE owner_uuid uuid;
    BEGIN
      IF TG_ARGV[0] = 'presentation' THEN
        IF TG_TABLE_NAME = 'form_presentation_elements' THEN
          IF TG_OP = 'DELETE' THEN owner_uuid := OLD.id; ELSE owner_uuid := NEW.id; END IF;
        ELSE
          IF TG_OP = 'DELETE' THEN owner_uuid := OLD.element_id; ELSE owner_uuid := NEW.element_id; END IF;
        END IF;
        PERFORM quick_train_check_form_presentation(owner_uuid);
      ELSE
        IF TG_TABLE_NAME = 'form_question_definitions' THEN
          IF TG_OP = 'DELETE' THEN owner_uuid := OLD.id; ELSE owner_uuid := NEW.id; END IF;
        ELSE
          IF TG_OP = 'DELETE' THEN owner_uuid := OLD.question_id; ELSE owner_uuid := NEW.question_id; END IF;
        END IF;
        PERFORM quick_train_check_form_question(owner_uuid);
      END IF;
      RETURN NULL;
    END; $$;
    $forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER forms_owner_guard BEFORE UPDATE OR DELETE ON forms FOR EACH ROW EXECUTE FUNCTION quick_train_form_owner_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_versions_owner_guard BEFORE INSERT OR UPDATE OR DELETE ON form_versions FOR EACH ROW EXECUTE FUNCTION quick_train_form_owner_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_input_slot_definitions_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_input_slot_definitions FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_input_field_requirements_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_input_field_requirements FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_question_definitions_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_question_definitions FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_text_constraints_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_text_constraints FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_integer_constraints_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_integer_constraints FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_decimal_constraints_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_decimal_constraints FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_selection_constraints_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_selection_constraints FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_annotation_constraints_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_annotation_constraints FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_input_sources_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_input_sources FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_question_options_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_question_options FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_label_sets_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_label_sets FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_labels_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_labels FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_presentation_elements_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_presentation_elements FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_instructions_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_instructions FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_headings_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_headings FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_sections_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_sections FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_bound_values_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_bound_values FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE TRIGGER form_question_placements_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON form_question_placements FOR EACH ROW EXECUTE FUNCTION quick_train_form_child_guard();$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_presentation_elements_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_presentation_elements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_instructions_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_instructions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_headings_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_headings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_sections_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_sections DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_bound_values_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_bound_values DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_question_placements_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_question_placements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('presentation');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_question_definitions_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_question_definitions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_text_constraints_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_text_constraints DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_integer_constraints_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_integer_constraints DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_decimal_constraints_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_decimal_constraints DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_selection_constraints_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_selection_constraints DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_annotation_constraints_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_annotation_constraints DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_input_sources_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_input_sources DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    EXECUTE $forms_ddl$CREATE CONSTRAINT TRIGGER form_question_options_typed_guard AFTER INSERT OR UPDATE OR DELETE ON form_question_options DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quick_train_form_typed_trigger('question');$forms_ddl$;
    END $forms_migration$;
    """)
  end
end
