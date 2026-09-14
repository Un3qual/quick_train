defmodule QuickTrain.Tasks.Responses.Inputs.TaskInputSelectionInput do
  @moduledoc "One selected task input, with a position only for rankings."
  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :task_input_id, :uuid, allow_nil?: false, public?: true
    attribute :position, :integer, public?: true, constraints: [min: 0]
  end

  graphql do
    type :task_input_selection_input
  end
end
