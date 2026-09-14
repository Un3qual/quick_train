defmodule QuickTrain.Tasks.Context.QuestionDefinition do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Questions.QuestionDefinition,
    fields: [
      :id,
      :family,
      :prompt,
      :key,
      :inserted_at,
      :updated_at,
      :version_id,
      :input_slot_id,
      :renderer,
      :source_requirement_id
    ],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    has_one :text_constraints, QuickTrain.Tasks.Context.TextConstraints,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true

    has_one :integer_constraints, QuickTrain.Tasks.Context.IntegerConstraints,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true

    has_one :decimal_constraints, QuickTrain.Tasks.Context.DecimalConstraints,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true

    has_one :selection_constraints, QuickTrain.Tasks.Context.SelectionConstraints,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true

    has_one :annotation_constraints, QuickTrain.Tasks.Context.AnnotationConstraints,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true

    belongs_to :input_slot, QuickTrain.Tasks.Context.InputSlotDefinition,
      source_attribute: :input_slot_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true

    belongs_to :source_requirement, QuickTrain.Tasks.Context.InputFieldRequirement,
      source_attribute: :source_requirement_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true

    has_many :options, QuickTrain.Tasks.Context.QuestionOption,
      source_attribute: :id,
      destination_attribute: :question_id,
      public?: true
  end

  graphql do
    type :task_form_question_definition
    derive_filter? false
    derive_sort? false

    relationships [
      :text_constraints,
      :integer_constraints,
      :decimal_constraints,
      :selection_constraints,
      :annotation_constraints,
      :input_slot,
      :source_requirement,
      :options
    ]

    paginate_relationship_with options: :relay
  end
end
