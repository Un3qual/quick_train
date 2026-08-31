defmodule QuickTrain.Datasets.Dataset do
  @moduledoc "Stable organization-owned container for versioned normalized records."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    has_many :schema_versions, QuickTrain.Datasets.DatasetSchemaVersion
  end

  actions do
    defaults [:read]

    create :create_dataset do
      accept [:organization_id, :key, :name]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      pagination keyset?: true,
                 offset?: false,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
    policy action(:create_dataset) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.manage"}
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset
  end

  postgres do
    table "datasets"
    repo QuickTrain.Repo
    identity_index_names organization_key: "datasets_organization_key_index"

    references do
      reference :organization, on_delete: :restrict, name: "datasets_organization_id_fkey"
    end

    custom_indexes do
      index [:id, :organization_id],
        unique: true,
        name: "datasets_id_organization_id_index"

      index [:organization_id], name: "datasets_organization_id_index"
    end
  end

  identities do
    identity :organization_key, [:organization_id, :key]
  end
end
