defmodule QuickTrain.Datasets.DatasetItem do
  @moduledoc "Stable identity for one item within an organization dataset."

  alias QuickTrain.Datasets.{Dataset, DatasetItemRevision}
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :external_key, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, Dataset,
      allow_nil?: false,
      public?: true

    has_many :revisions, DatasetItemRevision,
      destination_attribute: :item_id,
      public?: true
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    create :create_internal do
      accept [:id, :organization_id, :dataset_id, :external_key]
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and dataset_id == ^arg(:dataset_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination keyset?: true,
                 default_limit: 50,
                 max_page_size: 100
    end
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Datasets.Dataset"]), :items)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetItemRevision"]),
                     :item
                   )
    end

    policy action(:list_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "datasets.read"}
    end
  end

  graphql do
    complexity {Module.concat(["QuickTrain.Datasets"]), :connection_complexity}
    derive_filter? false
    derive_sort? false
    type :dataset_item
    relationships [:dataset, :revisions]
    paginate_relationship_with revisions: :relay
  end

  postgres do
    table "dataset_items"
    repo QuickTrain.Repo

    references do
      reference :organization,
        on_delete: :restrict,
        name: "dataset_items_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_items_dataset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]
    end

    custom_indexes do
      index [:id, :dataset_id, :organization_id],
        unique: true,
        name: "dataset_items_id_dataset_organization_index"

      index [:dataset_id, :external_key],
        unique: true,
        where: "external_key IS NOT NULL",
        name: "dataset_items_dataset_external_key_index"

      index [:dataset_id, :inserted_at, :id], name: "dataset_items_dataset_cursor_index"
    end
  end
end
