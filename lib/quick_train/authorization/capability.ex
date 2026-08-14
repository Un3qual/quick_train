defmodule QuickTrain.Authorization.Capability do
  @moduledoc "A stable, product-defined permission key."

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "capabilities"
    repo QuickTrain.Repo
    identity_index_names key: "capabilities_key_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :description, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:key, :description]
      upsert? true
      upsert_identity :key
      upsert_fields [:description]
      return_skipped_upsert? true
    end
  end

  identities do
    identity :key, [:key]
  end
end
