defmodule QuickTrain.Forms do
  @moduledoc "Reusable organization-owned form definitions and immutable published versions."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Forms.Form
    resource QuickTrain.Forms.FormVersion
    resource QuickTrain.Forms.Inputs.InputSlotDefinition
    resource QuickTrain.Forms.Inputs.InputFieldRequirement
    resource QuickTrain.Forms.Questions.QuestionDefinition
    resource QuickTrain.Forms.Questions.Constraints.TextConstraints
    resource QuickTrain.Forms.Questions.Constraints.IntegerConstraints
    resource QuickTrain.Forms.Questions.Constraints.DecimalConstraints
    resource QuickTrain.Forms.Questions.Constraints.SelectionConstraints
    resource QuickTrain.Forms.Questions.Constraints.AnnotationConstraints
    resource QuickTrain.Forms.Questions.InputSource
    resource QuickTrain.Forms.Questions.QuestionOption
    resource QuickTrain.Forms.Labels.LabelSet
    resource QuickTrain.Forms.Labels.Label
    resource QuickTrain.Forms.Presentation.PresentationElement
    resource QuickTrain.Forms.Presentation.Instruction
    resource QuickTrain.Forms.Presentation.Heading
    resource QuickTrain.Forms.Presentation.Section
    resource QuickTrain.Forms.Presentation.BoundValue
    resource QuickTrain.Forms.Presentation.QuestionPlacement
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
      action QuickTrain.Forms.Form, :create_form, :create_form, args: [:organization_id, :key]

      action QuickTrain.Forms.FormVersion, :create_form_draft, :create_draft,
        args: [:organization_id, :form_id, :title, :description]

      action QuickTrain.Forms.FormVersion, :copy_published_form, :copy_published,
        args: [:organization_id, :form_id, :source_version_id]

      action QuickTrain.Forms.FormVersion, :update_form_draft, :update_draft,
        args: [:organization_id, :version_id, :title, :description]

      action QuickTrain.Forms.FormVersion, :publish_form_version, :publish,
        args: [:organization_id, :version_id]

      action QuickTrain.Forms.Inputs.InputSlotDefinition,
             :add_form_input_slot_definition,
             :add_to_draft, args: [:organization_id, :version_id, :key, :minimum, :maximum]

      action QuickTrain.Forms.Inputs.InputSlotDefinition,
             :update_form_input_slot_definition,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.Inputs.InputSlotDefinition,
             :remove_form_input_slot_definition,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Inputs.InputFieldRequirement,
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

      action QuickTrain.Forms.Inputs.InputFieldRequirement,
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

      action QuickTrain.Forms.Inputs.InputFieldRequirement,
             :remove_form_input_field_requirement,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.QuestionDefinition,
             :add_form_question_definition,
             :add_to_draft,
             args: [:organization_id, :version_id, :key, :prompt, :family, :renderer]

      action QuickTrain.Forms.Questions.QuestionDefinition,
             :update_form_question_definition,
             :update_in_draft,
             args: [:organization_id, :version_id, :id, :prompt, :family, :renderer]

      action QuickTrain.Forms.Questions.QuestionDefinition,
             :remove_form_question_definition,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.Constraints.TextConstraints,
             :add_form_text_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.Questions.Constraints.TextConstraints,
             :update_form_text_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.Questions.Constraints.TextConstraints,
             :remove_form_text_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
             :add_form_integer_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
             :update_form_integer_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.Questions.Constraints.IntegerConstraints,
             :remove_form_integer_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
             :add_form_decimal_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
             :update_form_decimal_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.Questions.Constraints.DecimalConstraints,
             :remove_form_decimal_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
             :add_form_selection_constraints,
             :add_to_draft,
             args: [:organization_id, :version_id, :minimum, :maximum, :question_id]

      action QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
             :update_form_selection_constraints,
             :update_in_draft, args: [:organization_id, :version_id, :id, :minimum, :maximum]

      action QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
             :remove_form_selection_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
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

      action QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
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

      action QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
             :remove_form_annotation_constraints,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.InputSource, :add_form_input_source, :add_to_draft,
        args: [
          :organization_id,
          :version_id,
          :question_id,
          :input_slot_id,
          :source_requirement_id
        ]

      action QuickTrain.Forms.Questions.InputSource, :update_form_input_source, :update_in_draft,
        args: [:organization_id, :version_id, :id, :input_slot_id, :source_requirement_id]

      action QuickTrain.Forms.Questions.InputSource,
             :remove_form_input_source,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.QuestionOption, :add_form_question_option, :add_to_draft,
        args: [:organization_id, :version_id, :key, :label, :position, :question_id]

      action QuickTrain.Forms.Questions.QuestionOption,
             :update_form_question_option,
             :update_in_draft, args: [:organization_id, :version_id, :id, :label, :position]

      action QuickTrain.Forms.Questions.QuestionOption,
             :remove_form_question_option,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Questions.QuestionOption, :reorder_form_question_option, :reorder,
        args: [:organization_id, :version_id, :question_id, :ids]

      action QuickTrain.Forms.Labels.LabelSet, :add_form_label_set, :add_to_draft,
        args: [:organization_id, :version_id, :key, :name]

      action QuickTrain.Forms.Labels.LabelSet, :update_form_label_set, :update_in_draft,
        args: [:organization_id, :version_id, :id, :name]

      action QuickTrain.Forms.Labels.LabelSet, :remove_form_label_set, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Labels.Label, :add_form_label, :add_to_draft,
        args: [:organization_id, :version_id, :key, :text, :position, :label_set_id]

      action QuickTrain.Forms.Labels.Label, :update_form_label, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text, :position]

      action QuickTrain.Forms.Labels.Label, :remove_form_label, :remove_from_draft,
        args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Labels.Label, :reorder_form_label, :reorder,
        args: [:organization_id, :version_id, :label_set_id, :ids]

      action QuickTrain.Forms.Presentation.PresentationElement,
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

      action QuickTrain.Forms.Presentation.PresentationElement,
             :update_form_presentation_element,
             :update_in_draft, args: [:organization_id, :version_id, :id, :position]

      action QuickTrain.Forms.Presentation.PresentationElement,
             :remove_form_presentation_element,
             :remove_from_draft, args: [:organization_id, :version_id, :id]

      action QuickTrain.Forms.Presentation.PresentationElement,
             :reorder_form_presentation_element,
             :reorder, args: [:organization_id, :version_id, :ids]

      action QuickTrain.Forms.Presentation.Instruction,
             :update_form_instruction,
             :update_in_draft, args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.Presentation.Heading, :update_form_heading, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.Presentation.Section, :update_form_section, :update_in_draft,
        args: [:organization_id, :version_id, :id, :text]

      action QuickTrain.Forms.Presentation.BoundValue, :update_form_bound_value, :update_in_draft,
        args: [:organization_id, :version_id, :id, :requirement_id]

      action QuickTrain.Forms.Presentation.QuestionPlacement,
             :update_form_question_placement,
             :update_in_draft, args: [:organization_id, :version_id, :id, :question_id]
    end
  end

  def connection_complexity(arguments, child_complexity, _info) do
    page_size = arguments[:first] || arguments[:last] || 100
    1 + Kernel.max(page_size, 0) * Kernel.max(child_complexity, 1)
  end
end
