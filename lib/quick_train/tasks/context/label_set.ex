defmodule QuickTrain.Tasks.Context.LabelSet do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Labels.LabelSet,
    fields: [:id, :name, :key, :inserted_at, :updated_at, :version_id],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  relationships do
    has_many :labels, QuickTrain.Tasks.Context.Label,
      source_attribute: :id,
      destination_attribute: :label_set_id,
      public?: true
  end

  graphql do
    type :task_form_label_set
    derive_filter? false
    derive_sort? false
    relationships [:labels]
    paginate_relationship_with labels: :relay
  end
end
