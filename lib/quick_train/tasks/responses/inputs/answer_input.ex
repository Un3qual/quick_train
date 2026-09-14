defmodule QuickTrain.Tasks.Responses.Inputs.AnswerInput do
  @moduledoc "Typed input for replacing one complete question outcome."
  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :outcome, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:answered, :skipped]]

    attribute :family, QuickTrain.Forms.Types.AnswerFamily, allow_nil?: false, public?: true
    attribute :text_value, :string, public?: true, constraints: [trim?: false, allow_empty?: true]

    attribute :integer_value, :integer,
      public?: true,
      constraints: [min: -2_147_483_648, max: 2_147_483_647]

    attribute :decimal_value, :decimal, public?: true
    attribute :boolean_value, :boolean, public?: true
    attribute :reason, :string, public?: true, constraints: [trim?: false, allow_empty?: true]

    attribute :explanation, :string,
      public?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :option_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true

    attribute :inputs, {:array, QuickTrain.Tasks.Responses.Inputs.TaskInputSelectionInput},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :spans, {:array, QuickTrain.Tasks.Responses.Inputs.TextSpanInput},
      allow_nil?: false,
      default: [],
      public?: true
  end

  graphql do
    type :task_answer_input
  end
end
