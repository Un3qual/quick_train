defmodule QuickTrain.Datasets.DatasetImportSummary do
  @moduledoc "Derived lifecycle and row counts for one retained import."

  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :import_id, :uuid, allow_nil?: false, public?: true
    attribute :phase, :string, allow_nil?: false, public?: true
    attribute :lifecycle, :string, allow_nil?: false, public?: true
    attribute :row_count, :integer, allow_nil?: false, public?: true
    attribute :pending, :integer, allow_nil?: false, public?: true
    attribute :succeeded, :integer, allow_nil?: false, public?: true
    attribute :unchanged, :integer, allow_nil?: false, public?: true
    attribute :failed, :integer, allow_nil?: false, public?: true
  end

  graphql do
    type :dataset_import_summary
  end
end
