defmodule QuickTrain.Tasks.Access.BoundValue do
  @moduledoc "One exact bound input value, including explicit optional absence."
  use Ash.Resource, data_layer: :embedded, extensions: [AshGraphql.Resource]

  attributes do
    attribute :task_input_id, :uuid, public?: true, allow_nil?: false
    attribute :revision_id, :uuid, public?: true, allow_nil?: false
    attribute :requirement_id, :uuid, public?: true, allow_nil?: false
    attribute :field_definition_id, :uuid, public?: true, allow_nil?: false
    attribute :binding_id, :uuid, public?: true, allow_nil?: false
    attribute :missing, :boolean, public?: true, allow_nil?: false

    attribute :asset, QuickTrain.Assets.AssetSummary, public?: true

    attribute :value, :struct,
      public?: true,
      writable?: false,
      constraints: [instance_of: Module.concat(["QuickTrain.Datasets.DatasetValue"])]
  end

  graphql do
    type :task_bound_value
  end
end
