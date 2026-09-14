defmodule QuickTrain.Tasks.Context.Asset do
  @moduledoc false
  use QuickTrain.Tasks.Context.Resource,
    source: QuickTrain.Assets.Asset,
    fields: [
      :id,
      :byte_size,
      :state,
      :width,
      :sha256,
      :organization_id,
      :canonical_asset_id,
      :failure_reason,
      :height,
      :media_type,
      :staging_expires_at
    ],
    definition?: false,
    sort: [id: :asc]

  graphql do
    type :task_asset
    derive_filter? false
    derive_sort? false
    relationships []
    attribute_types sha256: :string
  end
end
