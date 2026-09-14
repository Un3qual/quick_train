defmodule QuickTrain.Tasks.Reviews.QuestionReview.Input do
  @moduledoc "One attributable question decision in an atomic review batch."
  use Ash.Resource, data_layer: :embedded, extensions: [AshGraphql.Resource]

  attributes do
    attribute :question_response_id, :uuid, allow_nil?: false, public?: true
    attribute :request_key, :uuid, allow_nil?: false, public?: true
    attribute :expected_predecessor_id, :uuid, public?: true

    attribute :verdict, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:accept, :reject]]

    attribute :reason, :string, public?: true, constraints: [trim?: false, allow_empty?: true]
  end

  actions do
    defaults create: [
               :question_response_id,
               :request_key,
               :expected_predecessor_id,
               :verdict,
               :reason
             ],
             update: [
               :question_response_id,
               :request_key,
               :expected_predecessor_id,
               :verdict,
               :reason
             ]
  end

  graphql do
    type :question_review_request
  end
end
