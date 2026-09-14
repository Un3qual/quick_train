defmodule QuickTrain.Projects.GroupInput do
  @moduledoc "One authored cohort item and its position within a form slot."
  use Ash.Resource, data_layer: :embedded, extensions: [AshGraphql.Resource]

  attributes do
    attribute :project_item_id, :uuid, allow_nil?: false, public?: true
    attribute :input_slot_id, :uuid, allow_nil?: false, public?: true

    attribute :position, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 2_147_483_647]
  end

  actions do
    defaults create: [:project_item_id, :input_slot_id, :position],
             update: [:project_item_id, :input_slot_id, :position]
  end

  graphql do
    type :project_group_input
  end
end
