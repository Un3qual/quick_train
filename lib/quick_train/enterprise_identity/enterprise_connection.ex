defmodule QuickTrain.EnterpriseIdentity.EnterpriseConnection do
  @moduledoc "An organization-owned enterprise SSO or directory connection."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.EnterpriseIdentity.Directory
  alias QuickTrain.Organizations.Organization

  postgres do
    table "enterprise_connections"
    repo QuickTrain.Repo

    unique_index_names [
      {[:provider, :external_id], "enterprise_connections_provider_external_index"}
    ]
  end

  graphql do
    type :enterprise_connection
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :configuration, :map, allow_nil?: false, public?: true, default: %{}

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      public?: true

    has_many :directories, Directory, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:organization_id, :provider, :external_id, :status, :configuration]
      upsert? true
      upsert_identity :provider_external
      upsert_fields [:organization_id, :status, :configuration]
      return_skipped_upsert? true
    end
  end

  identities do
    identity :provider_external, [:provider, :external_id]
  end
end
