defmodule QuickTrain.Tasks.Context.InputFieldRequirement do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Inputs.InputFieldRequirement,
    fields: [
      :id,
      :key,
      :required,
      :cardinality,
      :inserted_at,
      :updated_at,
      :version_id,
      :input_slot_id,
      :intended_use,
      :value_family
    ],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  graphql do
    type :task_form_input_field_requirement
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
