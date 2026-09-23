defmodule QuickTrain.Tasks.Task.Input do
  @moduledoc "One authored revision and its position within a form slot."
  use Ash.Resource, data_layer: :embedded, extensions: [AshGraphql.Resource]

  attributes do
    attribute :revision_id, :uuid, allow_nil?: false, public?: true
    attribute :input_slot_id, :uuid, allow_nil?: false, public?: true

    attribute :position, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 2_147_483_647]
  end

  actions do
    defaults create: [:revision_id, :input_slot_id, :position],
             update: [:revision_id, :input_slot_id, :position]
  end

  graphql do
    type :task_input_definition
  end
end
