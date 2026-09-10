defmodule QuickTrain.Forms do
  @moduledoc "Reusable organization-owned form definitions and immutable published versions."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Forms.Form do
      define :create_form, action: :create_form, args: [:organization_id]

      define :lock_form,
        action: :lock_for_allocation,
        args: [:id, :organization_id],
        get?: true,
        not_found_error?: false

      define :get_form, action: :get_scoped, args: [:organization_id, :id]
      define :list_forms, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.FormVersion do
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

    resource QuickTrain.Forms.Inputs.InputSlotDefinition do
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

    resource QuickTrain.Forms.Inputs.InputFieldRequirement do
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

    resource QuickTrain.Forms.Questions.QuestionDefinition do
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

    resource QuickTrain.Forms.Questions.Constraints.TextConstraints do
      define :add_form_text_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_text_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_text_constraints,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_text_constraints, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_text_constraints, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.Constraints.IntegerConstraints do
      define :add_form_integer_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_integer_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_integer_constraints,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_integer_constraints, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_integer_constraints, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.Constraints.DecimalConstraints do
      define :add_form_decimal_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_decimal_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_decimal_constraints,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_decimal_constraints, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_decimal_constraints, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.Constraints.SelectionConstraints do
      define :add_form_selection_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_selection_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_selection_constraints,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_selection_constraints, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_selection_constraints, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.Constraints.AnnotationConstraints do
      define :add_form_annotation_constraints, action: :add_to_draft, args: [:organization_id]

      define :update_form_annotation_constraints,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_annotation_constraints,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_annotation_constraints, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_annotation_constraints, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.InputSource do
      define :add_form_input_source, action: :add_to_draft, args: [:organization_id]

      define :update_form_input_source,
        action: :update_in_draft,
        args: [:organization_id]

      define :remove_form_input_source,
        action: :remove_from_draft,
        args: [:organization_id]

      define :get_form_input_source, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_input_sources, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Questions.QuestionOption do
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

    resource QuickTrain.Forms.Labels.LabelSet do
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

    resource QuickTrain.Forms.Labels.Label do
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

    resource QuickTrain.Forms.Presentation.PresentationElement do
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

    resource QuickTrain.Forms.Presentation.Instruction do
      define :update_form_instruction,
        action: :update_in_draft,
        args: [:organization_id]

      define :get_form_instruction, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_instructions, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Presentation.Heading do
      define :update_form_heading,
        action: :update_in_draft,
        args: [:organization_id]

      define :get_form_heading, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_headings, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Presentation.Section do
      define :update_form_section,
        action: :update_in_draft,
        args: [:organization_id]

      define :get_form_section, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_sections, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Presentation.BoundValue do
      define :update_form_bound_value,
        action: :update_in_draft,
        args: [:organization_id]

      define :get_form_bound_value, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_bound_values, action: :list_scoped, args: [:organization_id]
    end

    resource QuickTrain.Forms.Presentation.QuestionPlacement do
      define :update_form_question_placement,
        action: :update_in_draft,
        args: [:organization_id]

      define :get_form_question_placement, action: :get_scoped, args: [:organization_id, :id]
      define :list_form_question_placements, action: :list_scoped, args: [:organization_id]
    end
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

      list QuickTrain.Forms.Inputs.InputSlotDefinition,
           :form_input_slot_definitions,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Inputs.InputFieldRequirement,
           :form_input_field_requirements,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Questions.QuestionDefinition,
           :form_question_definitions,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Questions.QuestionOption, :form_question_options, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Labels.LabelSet, :form_label_sets, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Labels.Label, :form_labels, :list_scoped,
        relay?: true,
        paginate_with: :keyset,
        complexity: {__MODULE__, :connection_complexity}

      list QuickTrain.Forms.Presentation.PresentationElement,
           :form_presentation_elements,
           :list_scoped,
           relay?: true,
           paginate_with: :keyset,
           complexity: {__MODULE__, :connection_complexity}

      read_one QuickTrain.Forms.FormVersion, :form_version, :get_scoped
    end

    mutations do
      create QuickTrain.Forms.Form, :create_form, :create_form, args: [:organization_id, :key]

      create QuickTrain.Forms.FormVersion, :create_form_draft, :create_draft,
        args: [:organization_id, :form_id, :title, :description]

      action QuickTrain.Forms.FormVersion, :copy_published_form, :copy_published,
        args: [:organization_id, :form_id, :source_version_id]

      update QuickTrain.Forms.FormVersion, :update_form_draft, :update_draft,
        args: [:organization_id, :title, :description],
        read_action: :read_for_authoring

      action QuickTrain.Forms.FormVersion, :publish_form_version, :publish,
        args: [:organization_id, :version_id]

      create QuickTrain.Forms.Inputs.InputSlotDefinition,
             :add_form_input_slot_definition,
             :add_to_draft, args: [:organization_id, :version_id, :key, :minimum, :maximum]

      update QuickTrain.Forms.Inputs.InputSlotDefinition,
             :update_form_input_slot_definition,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Inputs.InputSlotDefinition,
              :remove_form_input_slot_definition,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Inputs.InputFieldRequirement,
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

      update QuickTrain.Forms.Inputs.InputFieldRequirement,
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

      destroy QuickTrain.Forms.Inputs.InputFieldRequirement,
              :remove_form_input_field_requirement,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.QuestionDefinition,
             :add_form_question_definition,
             :add_to_draft,
             args: [:organization_id, :version_id, :key, :prompt, :family, :renderer]

      update QuickTrain.Forms.Questions.QuestionDefinition,
             :update_form_question_definition,
             :update_in_draft,
             args: [:organization_id, :version_id, :prompt, :family, :renderer],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.QuestionDefinition,
              :remove_form_question_definition,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.Constraints.TextConstraints,
             :add_form_text_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update QuickTrain.Forms.Questions.Constraints.TextConstraints,
             :update_form_text_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.Constraints.TextConstraints,
              :remove_form_text_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
             :add_form_integer_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
             :update_form_integer_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
              :remove_form_integer_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
             :add_form_decimal_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
             :update_form_decimal_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
              :remove_form_decimal_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
             :add_form_selection_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      update QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
             :update_form_selection_constraints,
             :update_in_draft,
             args: [:organization_id, :version_id, :minimum, :maximum],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
              :remove_form_selection_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
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

      update QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
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

      destroy QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
              :remove_form_annotation_constraints,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.InputSource, :add_form_input_source, :add_to_draft,
        args: [
          :organization_id,
          :version_id,
          :question_id,
          :input_slot_id,
          :source_requirement_id
        ]

      update QuickTrain.Forms.Questions.InputSource, :update_form_input_source, :update_in_draft,
        args: [:organization_id, :version_id, :input_slot_id, :source_requirement_id],
        read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.InputSource,
              :remove_form_input_source,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      create QuickTrain.Forms.Questions.QuestionOption, :add_form_question_option, :add_to_draft,
        args: [:organization_id, :version_id, :key, :label, :position, :question_id]

      update QuickTrain.Forms.Questions.QuestionOption,
             :update_form_question_option,
             :update_in_draft,
             args: [:organization_id, :version_id, :label, :position],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Questions.QuestionOption,
              :remove_form_question_option,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      action QuickTrain.Forms.Questions.QuestionOption, :reorder_form_question_option, :reorder,
        args: [:organization_id, :version_id, :question_id, :ids]

      create QuickTrain.Forms.Labels.LabelSet, :add_form_label_set, :add_to_draft,
        args: [:organization_id, :version_id, :key, :name]

      update QuickTrain.Forms.Labels.LabelSet, :update_form_label_set, :update_in_draft,
        args: [:organization_id, :version_id, :name],
        read_action: :read_for_authoring

      destroy QuickTrain.Forms.Labels.LabelSet, :remove_form_label_set, :remove_from_draft,
        args: [:organization_id, :version_id],
        read_action: :read_for_authoring

      create QuickTrain.Forms.Labels.Label, :add_form_label, :add_to_draft,
        args: [:organization_id, :version_id, :key, :text, :position, :label_set_id]

      update QuickTrain.Forms.Labels.Label, :update_form_label, :update_in_draft,
        args: [:organization_id, :version_id, :text, :position],
        read_action: :read_for_authoring

      destroy QuickTrain.Forms.Labels.Label, :remove_form_label, :remove_from_draft,
        args: [:organization_id, :version_id],
        read_action: :read_for_authoring

      action QuickTrain.Forms.Labels.Label, :reorder_form_label, :reorder,
        args: [:organization_id, :version_id, :label_set_id, :ids]

      create QuickTrain.Forms.Presentation.PresentationElement,
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

      update QuickTrain.Forms.Presentation.PresentationElement,
             :update_form_presentation_element,
             :update_in_draft,
             args: [:organization_id, :version_id, :position],
             read_action: :read_for_authoring

      destroy QuickTrain.Forms.Presentation.PresentationElement,
              :remove_form_presentation_element,
              :remove_from_draft,
              args: [:organization_id, :version_id],
              read_action: :read_for_authoring

      action QuickTrain.Forms.Presentation.PresentationElement,
             :reorder_form_presentation_element,
             :reorder, args: [:organization_id, :version_id, :ids]

      update QuickTrain.Forms.Presentation.Instruction,
             :update_form_instruction,
             :update_in_draft,
             args: [:organization_id, :version_id, :text],
             read_action: :read_for_authoring

      update QuickTrain.Forms.Presentation.Heading, :update_form_heading, :update_in_draft,
        args: [:organization_id, :version_id, :text],
        read_action: :read_for_authoring

      update QuickTrain.Forms.Presentation.Section, :update_form_section, :update_in_draft,
        args: [:organization_id, :version_id, :text],
        read_action: :read_for_authoring

      update QuickTrain.Forms.Presentation.BoundValue, :update_form_bound_value, :update_in_draft,
        args: [:organization_id, :version_id, :requirement_id],
        read_action: :read_for_authoring

      update QuickTrain.Forms.Presentation.QuestionPlacement,
             :update_form_question_placement,
             :update_in_draft,
             args: [:organization_id, :version_id, :question_id],
             read_action: :read_for_authoring
    end
  end

  def connection_complexity(arguments, child_complexity, _info) do
    page_size = arguments[:first] || arguments[:last] || 100
    1 + Kernel.max(page_size, 0) * Kernel.max(child_complexity, 1)
  end
end
