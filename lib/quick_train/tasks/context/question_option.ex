defmodule QuickTrain.Tasks.Context.QuestionOption do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Forms.Questions.QuestionOption,
    fields: [:id, :label, :position, :key, :inserted_at, :updated_at, :version_id, :question_id],
    definition?: true,
    sort: [position: :asc, id: :asc]

  graphql do
    type :task_form_question_option
    derive_filter? false
    derive_sort? false
    relationships []
  end
end
