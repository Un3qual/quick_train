defmodule QuickTrain.Tasks.Context.PresentationElement do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Presentation.PresentationElement,
    fields: [
      :id,
      :position,
      :text,
      :kind,
      :inserted_at,
      :updated_at,
      :version_id,
      :question_id,
      :requirement_id
    ],
    definition?: true,
    sort: [position: :asc, id: :asc]

  relationships do
    belongs_to :requirement, QuickTrain.Tasks.Context.InputFieldRequirement,
      source_attribute: :requirement_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true

    belongs_to :question, QuickTrain.Tasks.Context.QuestionDefinition,
      source_attribute: :question_id,
      destination_attribute: :id,
      define_attribute?: false,
      public?: true
  end

  graphql do
    type :task_form_presentation_element
    derive_filter? false
    derive_sort? false
    relationships [:requirement, :question]
  end
end
