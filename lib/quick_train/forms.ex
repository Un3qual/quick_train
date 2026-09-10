defmodule QuickTrain.Forms do
  @moduledoc "Reusable organization-owned form definitions and immutable published versions."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Forms.Form
    resource QuickTrain.Forms.FormVersion
    resource QuickTrain.Forms.InputSlotDefinition
    resource QuickTrain.Forms.InputFieldRequirement
    resource QuickTrain.Forms.QuestionDefinition
    resource QuickTrain.Forms.TextConstraints
    resource QuickTrain.Forms.IntegerConstraints
    resource QuickTrain.Forms.DecimalConstraints
    resource QuickTrain.Forms.SelectionConstraints
    resource QuickTrain.Forms.AnnotationConstraints
    resource QuickTrain.Forms.InputSource
    resource QuickTrain.Forms.QuestionOption
    resource QuickTrain.Forms.LabelSet
    resource QuickTrain.Forms.Label
    resource QuickTrain.Forms.PresentationElement
    resource QuickTrain.Forms.Instruction
    resource QuickTrain.Forms.Heading
    resource QuickTrain.Forms.Section
    resource QuickTrain.Forms.BoundValue
    resource QuickTrain.Forms.QuestionPlacement
  end

  graphql do
    queries do
      list QuickTrain.Forms.Form, :forms, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.FormVersion, :form_versions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.InputSlotDefinition, :form_input_slot_definitions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.InputFieldRequirement, :form_input_field_requirements, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.QuestionDefinition, :form_question_definitions, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.QuestionOption, :form_question_options, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.LabelSet, :form_label_sets, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Label, :form_labels, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.PresentationElement, :form_presentation_elements, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      read_one QuickTrain.Forms.FormVersion, :form_version, :get_scoped
    end

    mutations do
      action QuickTrain.Forms.Form, :create_form, :create_form, args: [:organization_id, :key]

      action QuickTrain.Forms.FormVersion, :create_form_draft, :create_draft,
        args: [:organization_id, :form_id, :title, :description]

      action QuickTrain.Forms.FormVersion, :copy_published_form, :copy_published,
        args: [:organization_id, :form_id, :source_version_id]

      action QuickTrain.Forms.FormVersion, :update_form_draft, :update_draft,
        args: [:organization_id, :version_id, :title, :description]

      action QuickTrain.Forms.FormVersion, :publish_form_version, :publish,
        args: [:organization_id, :version_id]

      action QuickTrain.Forms.InputSlotDefinition, :add_form_input_slot_definition, :add_to_draft,
        args: [:organization_id, :version_id, :key, :minimum, :maximum]

      action QuickTrain.Forms.InputSlotDefinition,
             :update_form_input_slot_definition,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.InputSlotDefinition,
             :remove_form_input_slot_definition,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.InputFieldRequirement,
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

      action QuickTrain.Forms.InputFieldRequirement,
             :update_form_input_field_requirement,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :id,
               :value_family,
               :cardinality,
               :required,
               :intended_use
             ]

      action QuickTrain.Forms.InputFieldRequirement,
             :remove_form_input_field_requirement,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.QuestionDefinition, :add_form_question_definition, :add_to_draft,
        args: [:organization_id, :version_id, :key, :prompt, :family, :renderer]

      action QuickTrain.Forms.QuestionDefinition,
             :update_form_question_definition,
             :update_in_draft,
             args: [:organization_id, :version_id, :id, :prompt, :family, :renderer]

      action QuickTrain.Forms.QuestionDefinition,
             :remove_form_question_definition,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.TextConstraints, :add_form_text_constraints, :add_to_draft,
        args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.TextConstraints, :update_form_text_constraints, :update_in_draft,
        args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.TextConstraints, :remove_form_text_constraints, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.IntegerConstraints, :add_form_integer_constraints, :add_to_draft,
        args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.IntegerConstraints,
             :update_form_integer_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.IntegerConstraints,
             :remove_form_integer_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.DecimalConstraints, :add_form_decimal_constraints, :add_to_draft,
        args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.DecimalConstraints,
             :update_form_decimal_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.DecimalConstraints,
             :remove_form_decimal_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.SelectionConstraints,
             :add_form_selection_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.SelectionConstraints,
             :update_form_selection_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.SelectionConstraints,
             :remove_form_selection_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.AnnotationConstraints,
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

      action QuickTrain.Forms.AnnotationConstraints,
             :update_form_annotation_constraints,
             :update_in_draft,
             args: [
               :organization_id,
               :version_id,
               :id,
               :minimum,
               :maximum,
               :source_requirement_id,
               :label_set_id
             ]

      action QuickTrain.Forms.AnnotationConstraints,
             :remove_form_annotation_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.InputSource, :add_form_input_source, :add_to_draft,
        args: [
          :organization_id,
          :version_id,
          :question_id,
          :input_slot_id,
          :source_requirement_id
        ]

      action QuickTrain.Forms.InputSource, :update_form_input_source, :update_in_draft,
        args: [:organization_id, :version_id, :id, :input_slot_id, :source_requirement_id]

      action QuickTrain.Forms.InputSource, :remove_form_input_source, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.QuestionOption, :add_form_question_option, :add_to_draft,
        args: [:organization_id, :version_id, :key, :label, :position, :question_id]

      action QuickTrain.Forms.QuestionOption, :update_form_question_option, :update_in_draft,
        args: [:organization_id, :version_id, :id, :label, :position]

      action QuickTrain.Forms.QuestionOption, :remove_form_question_option, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.QuestionOption, :reorder_form_question_option, :reorder,
        args: [:organization_id, :version_id, :question_id, :ids]

      action QuickTrain.Forms.LabelSet, :add_form_label_set, :add_to_draft,
        args: [:organization_id, :version_id, :key, :name]

      action QuickTrain.Forms.LabelSet, :update_form_label_set, :update_in_draft,
        args: [:organization_id, :version_id, :id, :name]

      action QuickTrain.Forms.LabelSet, :remove_form_label_set, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Label, :add_form_label, :add_to_draft,
        args: [:organization_id, :version_id, :key, :text, :position, :label_set_id]

      action QuickTrain.Forms.Label, :update_form_label, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text, :position]

      action QuickTrain.Forms.Label, :remove_form_label, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Label, :reorder_form_label, :reorder,
        args: [:organization_id, :version_id, :label_set_id, :ids]

      action QuickTrain.Forms.PresentationElement, :add_form_presentation_element, :add_to_draft,
        args: [
          :organization_id,
          :version_id,
          :kind,
          :position,
          :text,
          :requirement_id,
          :question_id
        ]

      action QuickTrain.Forms.PresentationElement,
             :update_form_presentation_element,
             :update_in_draft, args: [:organization_id, :version_id, :id, :position]

      action QuickTrain.Forms.PresentationElement,
             :remove_form_presentation_element,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.PresentationElement, :reorder_form_presentation_element, :reorder,
        args: [:organization_id, :version_id, :ids]

      action QuickTrain.Forms.Instruction, :update_form_instruction, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.Heading, :update_form_heading, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.Section, :update_form_section, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.BoundValue, :update_form_bound_value, :update_in_draft,
        args: [:organization_id, :version_id, :id, :requirement_id]

      action QuickTrain.Forms.QuestionPlacement,
             :update_form_question_placement,
             :update_in_draft, args: [:organization_id, :version_id, :id, :question_id]
    end
  end

  def connection_complexity(arguments, child_complexity, _info) do
    page_size = arguments[:first] || arguments[:last] || 100
    1 + Kernel.max(page_size, 0) * Kernel.max(child_complexity, 1)
  end
end
