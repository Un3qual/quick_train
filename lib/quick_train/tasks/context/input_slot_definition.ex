defmodule QuickTrain.Tasks.Context.InputSlotDefinition do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Inputs.InputSlotDefinition,
    fields: [:id, :maximum, :key, :inserted_at, :updated_at, :version_id, :minimum],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    has_many :requirements, QuickTrain.Tasks.Context.InputFieldRequirement,
      source_attribute: :id,
      destination_attribute: :input_slot_id,
      public?: true
  end

  graphql do
    type :task_form_input_slot_definition
    derive_filter? false
    derive_sort? false
    relationships [:requirements]
    paginate_relationship_with requirements: :relay
  end
end
