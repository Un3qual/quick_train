defmodule QuickTrain.Authorization.Capability do
  @moduledoc "A stable, product-defined permission key."

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  postgres do
    table "capabilities"
    repo QuickTrain.Repo
    identity_index_names key: "capabilities_key_index"
  end

  graphql do
    type :capability
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
    end
  end

  identities do
    identity :key, [:key]
  end
end
