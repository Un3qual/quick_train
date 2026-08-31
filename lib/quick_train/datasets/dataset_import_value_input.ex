defmodule QuickTrain.Datasets.DatasetImportValueInput do
  @moduledoc "Fixed flat typed input accepted by one import row."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :field, :string, allow_nil?: false, public?: true
    attribute :text, :string, public?: true
    attribute :integer, :integer, public?: true
    attribute :decimal, :string, public?: true
    attribute :boolean, :boolean, public?: true
    attribute :utc_datetime, :string, public?: true
    attribute :asset_id, :uuid, public?: true
  end

  graphql do
    type :dataset_import_value_input
  end
end
