defmodule QuickTrain.Tasks.Context.SelectionConstraints do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Questions.Constraints.SelectionConstraints,
    fields: [:id, :maximum, :inserted_at, :updated_at, :version_id, :minimum, :question_id],
    definition?: true,
    sort: [inserted_at: :asc, id: :asc]

  graphql do
    type :task_form_selection_constraints
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
