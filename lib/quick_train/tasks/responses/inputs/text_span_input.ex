defmodule QuickTrain.Tasks.Responses.Inputs.TextSpanInput do
  @moduledoc "An exact labelled code-point range in one bound immutable source."
  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :task_input_id, :uuid, allow_nil?: false, public?: true
    attribute :source_value_id, :uuid, allow_nil?: false, public?: true
    attribute :label_id, :uuid, allow_nil?: false, public?: true
    attribute :start, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :end, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
  end

  validations do
    validate compare(:end, greater_than: :start)
  end

  graphql do
    type :task_text_span_input
  end
end
