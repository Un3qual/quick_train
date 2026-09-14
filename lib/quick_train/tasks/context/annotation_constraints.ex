defmodule QuickTrain.Tasks.Context.AnnotationConstraints do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
    fields: [
      :id,
      :maximum,
      :inserted_at,
      :updated_at,
      :version_id,
      :minimum,
      :question_id,
      :source_requirement_id,
      :label_set_id
    ],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    belongs_to :question, QuickTrain.Tasks.Context.QuestionDefinition,
      source_attribute: :question_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: false

    belongs_to :source_requirement, QuickTrain.Tasks.Context.InputFieldRequirement,
      source_attribute: :source_requirement_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true

    belongs_to :label_set, QuickTrain.Tasks.Context.LabelSet,
      source_attribute: :label_set_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true
  end

  calculations do
    calculate :source_convention,
              :string,
              Ash.Resource.Info.calculation(
                QuickTrain.Forms.Questions.Constraints.AnnotationConstraints,
                :source_convention
              ).calculation,
              public?: true
  end

  graphql do
    type :task_form_annotation_constraints
    derive_filter? false
    derive_sort? false
    relationships [:source_requirement, :label_set]
  end
end
