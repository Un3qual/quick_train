defmodule QuickTrain.Datasets.Dataset do
  @moduledoc "Stable organization-owned container for versioned normalized records."

  alias QuickTrain.Datasets.{DatasetItem, DatasetSchemaVersion}
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, :string,
      allow_nil?: false,
      public?: true

    attribute :name, :string,
      allow_nil?: false,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    has_many :schema_versions, DatasetSchemaVersion, public?: true

    has_many :items, DatasetItem, public?: true
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
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetSchemaVersion"]),
                     :dataset
                   )

      authorize_if accessing_from(Module.concat(["QuickTrain.Datasets.DatasetItem"]), :dataset)
      authorize_if accessing_from(Module.concat(["QuickTrain.Datasets.DatasetImport"]), :dataset)
    end

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
    relationships [:schema_versions, :items]
    paginate_relationship_with schema_versions: :relay, items: :relay
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
