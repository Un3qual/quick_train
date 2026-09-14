defmodule QuickTrain.Tasks.Context.FormVersion do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.FormVersion,
    fields: [
      :id,
      :version,
      :state,
      :description,
      :title,
      :published_at,
      :form_id,
      :inserted_at,
      :updated_at
    ],
    definition?: true,
    sort: [version: :asc, id: :asc]

  relationships do
    has_many :input_slots, QuickTrain.Tasks.Context.InputSlotDefinition,
      source_attribute: :id,
      destination_attribute: :version_id,
      public?: true

    has_many :requirements, QuickTrain.Tasks.Context.InputFieldRequirement,
      source_attribute: :id,
      destination_attribute: :version_id,
      public?: true

    has_many :questions, QuickTrain.Tasks.Context.QuestionDefinition,
      source_attribute: :id,
      destination_attribute: :version_id,
      public?: true

    has_many :elements, QuickTrain.Tasks.Context.PresentationElement,
      source_attribute: :id,
      destination_attribute: :version_id,
      public?: true

    has_many :label_sets, QuickTrain.Tasks.Context.LabelSet,
      source_attribute: :id,
      destination_attribute: :version_id,
      public?: true
  end

  graphql do
    type :task_form_version
    derive_filter? false
    derive_sort? false
    relationships [:input_slots, :requirements, :questions, :elements, :label_sets]

    paginate_relationship_with input_slots: :relay,
                               requirements: :relay,
                               questions: :relay,
                               elements: :relay,
                               label_sets: :relay
  end
end
