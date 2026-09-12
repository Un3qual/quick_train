defmodule QuickTrain.Forms do
  @moduledoc "Reusable organization-owned form definitions and immutable published versions."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Forms.{Form, FormVersion}
  alias QuickTrain.Forms.Inputs.{InputFieldRequirement, InputSlotDefinition}
  alias QuickTrain.Forms.Labels.{Label, LabelSet}
  alias QuickTrain.Forms.Presentation.PresentationElement

  alias QuickTrain.Forms.Questions.Constraints.{
    AnnotationConstraints,
    DecimalConstraints,
    IntegerConstraints,
    SelectionConstraints,
    TextConstraints
  }

  alias QuickTrain.Forms.Questions.{QuestionDefinition, QuestionOption}

  resources do
    resource Form do
      define :create_form, action: :create_form, args: [:organization_id]

      define :lock_form,
        action: :lock_for_allocation,
        args: [:id, :organization_id],
        get?: true,
        not_found_error?: false

      define :get_form, action: :get_scoped, args: [:organization_id, :id]
      define :list_forms, action: :list_scoped, args: [:organization_id]
    end

    resource FormVersion do
      define :create_form_draft, action: :create_draft, args: [:organization_id]
      define :copy_published_form, action: :copy_published, args: [:organization_id]

      define :update_form_draft,
        action: :update_draft,
        args: [:organization_id]

      define :publish_form_version, action: :publish, args: [:organization_id]

      define :lock_form_version,
        action: :lock_for_authoring,
        args: [:id, :organization_id],
        get?: true,
        not_found_error?: false

      define :get_form_version, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_versions, action: :list_scoped, args: [:organization_id]
    end

    resource InputSlotDefinition do
      define :add_form_input_slot_definition, action: :add_to_draft, args: [:organization_id]

      define :update_form_input_slot_definition,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_input_slot_definition,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_input_slot_definition, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_input_slot_definitions, action: :list_scoped, args: [:organization_id]
    end

    resource InputFieldRequirement do
      define :add_form_input_field_requirement, action: :add_to_draft, args: [:organization_id]

      define :update_form_input_field_requirement,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_input_field_requirement,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_input_field_requirement, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_input_field_requirements, action: :list_scoped, args: [:organization_id]
    end

    resource QuestionDefinition do
      define :add_form_question_definition, action: :add_to_draft, args: [:organization_id]

      define :update_form_question_definition,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_question_definition,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_question_definition, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_question_definitions, action: :list_scoped, args: [:organization_id]
    end

    resource TextConstraints do
      define :add_form_text_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_text_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_text_constraints,
        action: :remove_from_draft,
        args: [:organization_id]
    end

    resource IntegerConstraints do
      define :add_form_integer_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_integer_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_integer_constraints,
        action: :remove_from_draft,
        args: [:organization_id]
    end

    resource DecimalConstraints do
      define :add_form_decimal_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_decimal_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_decimal_constraints,
        action: :remove_from_draft,
        args: [:organization_id]
    end

    resource SelectionConstraints do
      define :add_form_selection_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_selection_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_selection_constraints,
        action: :remove_from_draft,
        args: [:organization_id]
    end

    resource AnnotationConstraints do
      define :add_form_annotation_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_annotation_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_annotation_constraints,
        action: :remove_from_draft,
        args: [:organization_id]
    end

    resource QuestionOption do
      define :add_form_question_option, action: :add_to_draft, args: [:organization_id]

      define :update_form_question_option,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_question_option,
        action: :remove_from_draft,
        args: [:organization_id]

      define :reorder_form_question_option, action: :reorder, args: [:organization_id]
      define :get_form_question_option, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_question_options, action: :list_scoped, args: [:organization_id]
    end

    resource LabelSet do
      define :add_form_label_set, action: :add_to_draft, args: [:organization_id]

      define :update_form_label_set,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_label_set,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_label_set, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_label_sets, action: :list_scoped, args: [:organization_id]
    end

    resource Label do
      define :add_form_label, action: :add_to_draft, args: [:organization_id]

      define :update_form_label,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_label,
        action: :remove_from_draft,
        args: [:organization_id]

      define :reorder_form_label, action: :reorder, args: [:organization_id]
      define :get_form_label, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_labels, action: :list_scoped, args: [:organization_id]
    end

    resource PresentationElement do
      define :add_form_presentation_element, action: :add_to_draft, args: [:organization_id]

      define :update_form_presentation_element,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_presentation_element,
        action: :remove_from_draft,
        args: [:organization_id]

      define :reorder_form_presentation_element, action: :reorder, args: [:organization_id]
      define :get_form_presentation_element, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_presentation_elements, action: :list_scoped, args: [:organization_id]
    end
  end

  graphql do
    queries do
      list Form, :forms, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list FormVersion, :form_versions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list InputSlotDefinition,
           :form_input_slot_definitions,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list InputFieldRequirement,
           :form_input_field_requirements,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list QuestionDefinition,
           :form_question_definitions,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list QuestionOption, :form_question_options, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list LabelSet, :form_label_sets, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list Label, :form_labels, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list PresentationElement,
           :form_presentation_elements,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      read_one FormVersion, :form_version, :get_scoped
    end

    mutations do
      create Form, :create_form, :create_form, args: [:organization_id, :key]

      create FormVersion, :create_form_draft, :create_draft,
        args: [:organization_id, :form_id, :title, :description]

      action FormVersion, :copy_published_form, :copy_published,
        args: [:organization_id, :form_id, :source_version_id]

      update FormVersion, :update_form_draft, :update_draft,
        args: [:organization_id, :title, :description],
        read_action: :read_for_authoring

      action FormVersion, :publish_form_version, :publish, args: [:organization_id, :version_id]

      create InputSlotDefinition,
             :add_form_input_slot_definition,
             :add_to_draft, args: [:organization_id, :version_id, :key, :minimum, :maximum]

      update InputSlotDefinition,
             :update_form_input_slot_definition,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy InputSlotDefinition,
              :remove_form_input_slot_definition,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create InputFieldRequirement,
             :add_form_input_field_requirement,
             :add_to_draft,
             args: [
               :organization_id,
               :version_id,
               :key,
               :value_family,
               :cardinality,
               :required,
               :intended_use,
               :input_slot_id
             ]

      update InputFieldRequirement,
             :update_form_input_field_requirement,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :value_family,
               :cardinality,
               :required,
               :intended_use
             ],
             read_action: :read_for_authoring

      destroy InputFieldRequirement,
              :remove_form_input_field_requirement,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuestionDefinition,
             :add_form_question_definition,
             :add_to_draft,
             args: [
               :organization_id,
               :version_id,
               :key,
               :prompt,
               :family,
               :renderer,
               :input_slot_id,
               :source_requirement_id
             ]

      update QuestionDefinition,
             :update_form_question_definition,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :prompt,
               :family,
               :renderer,
               :input_slot_id,
               :source_requirement_id
             ],
             read_action: :read_for_authoring

      destroy QuestionDefinition,
              :remove_form_question_definition,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create TextConstraints,
             :add_form_text_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update TextConstraints,
             :update_form_text_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy TextConstraints,
              :remove_form_text_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create IntegerConstraints,
             :add_form_integer_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update IntegerConstraints,
             :update_form_integer_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy IntegerConstraints,
              :remove_form_integer_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create DecimalConstraints,
             :add_form_decimal_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update DecimalConstraints,
             :update_form_decimal_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy DecimalConstraints,
              :remove_form_decimal_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create SelectionConstraints,
             :add_form_selection_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update SelectionConstraints,
             :update_form_selection_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy SelectionConstraints,
              :remove_form_selection_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create AnnotationConstraints,
             :add_form_annotation_constraints,
             :add_to_draft,
             args: [
               :organization_id,
               :version_id,
               :minimum,
               :maximum,
               :question_id,
               :source_requirement_id,
               :label_set_id
             ]

      update AnnotationConstraints,
             :update_form_annotation_constraints,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :minimum,
               :maximum,
               :source_requirement_id,
               :label_set_id
             ],
             read_action: :read_for_authoring

      destroy AnnotationConstraints,
              :remove_form_annotation_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuestionOption, :add_form_question_option, :add_to_draft,
        args: [:organization_id, :version_id, :key, :label, :position, :question_id]

      update QuestionOption,
             :update_form_question_option,
             :update_in_draft,
             args: [:organization_id, :version_id, :label, :position],
             read_action: :read_for_authoring

      destroy QuestionOption,
              :remove_form_question_option,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      action QuestionOption, :reorder_form_question_option, :reorder,
        args: [:organization_id, :version_id, :question_id, :ids]

      create LabelSet, :add_form_label_set, :add_to_draft,
        args: [:organization_id, :version_id, :key, :name]

      update LabelSet, :update_form_label_set, :update_in_draft,
        args: [:organization_id, :version_id, :name],
        read_action: :read_for_authoring

      destroy LabelSet, :remove_form_label_set, :remove_from_draft,
        args: [:organization_id, :version_id],
        read_action: :read_for_authoring

      create Label, :add_form_label, :add_to_draft,
        args: [:organization_id, :version_id, :key, :text, :position, :label_set_id]

      update Label, :update_form_label, :update_in_draft,
        args: [:organization_id, :version_id, :text, :position],
        read_action: :read_for_authoring

      destroy Label, :remove_form_label, :remove_from_draft,
        args: [:organization_id, :version_id],
        read_action: :read_for_authoring

      action Label, :reorder_form_label, :reorder,
        args: [:organization_id, :version_id, :label_set_id, :ids]

      create PresentationElement,
             :add_form_presentation_element,
             :add_to_draft,
             args: [
               :organization_id,
               :version_id,
               :kind,
               :position,
               :text,
               :requirement_id,
               :question_id
             ]

      update PresentationElement,
             :update_form_presentation_element,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :position,
               :text,
               :requirement_id,
               :question_id
             ],
             read_action: :read_for_authoring

      destroy PresentationElement,
              :remove_form_presentation_element,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      action PresentationElement,
             :reorder_form_presentation_element,
             :reorder, args: [:organization_id, :version_id, :ids]
    end
  end

  def connection_complexity(arguments, child_complexity, _info) do
    page_size = arguments[:first] || arguments[:last] || 50
    1 + Kernel.max(page_size, 0) * Kernel.max(child_complexity, 1)
  end
end
