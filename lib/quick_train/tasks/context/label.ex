defmodule QuickTrain.Tasks.Context.Label do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Labels.Label,
    fields: [:id, :position, :text, :key, :inserted_at, :updated_at, :version_id, :label_set_id],
    definition?: true,
    sort: [position: :asc, id: :asc]

  graphql do
    type :task_form_label
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
