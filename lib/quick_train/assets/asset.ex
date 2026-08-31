defmodule QuickTrain.Assets.Asset do
  @moduledoc "Immutable metadata and bounded lifecycle facts for one organization asset."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Assets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id, writable?: true

    attribute :state, QuickTrain.Assets.AssetState do
      allow_nil? false
      default :pending
      public? true
    end

    attribute :sha256, QuickTrain.Types.Sha256Digest do
      allow_nil? false
      public? true
    end

    attribute :byte_size, :integer do
      allow_nil? false
      public? true
    end

    attribute :media_type, :string do
      allow_nil? false
      public? true
    end

    attribute :width, :integer, public?: true
    attribute :height, :integer, public?: true

    attribute :staging_key, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :sealed_key, :string do
      sensitive? true
    end

    attribute :staging_expires_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :staging_cleaned_at, :utc_datetime_usec
    attribute :failure_reason, :string, public?: true
    attribute :operation_claim_kind, :atom, constraints: [one_of: [:finalize, :cleanup]]
    attribute :operation_claim_id, :uuid
    attribute :operation_claim_expires_at, :utc_datetime_usec
    attribute :publication_may_finish_at, :utc_datetime_usec
    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :canonical_asset, __MODULE__ do
      allow_nil? true
      attribute_public? true
      public? true
    end

    has_many :duplicate_assets, __MODULE__ do
      destination_attribute :canonical_asset_id
    end
  end

  actions do
    defaults [:read]

    read :get_scoped do
      get? true
      argument :asset_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:asset_id) and organization_id == ^arg(:organization_id))
    end

    action :register, QuickTrain.Assets.AssetRegistrationResult do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :sha256, :string, allow_nil?: false
      argument :byte_size, :integer, allow_nil?: false
      argument :media_type, :string, allow_nil?: false

      run {Module.concat(["QuickTrain.Assets.Asset.Actions.Register"]), []}
    end

    action :finalize, QuickTrain.Assets.AssetFinalizationResult do
      allow_nil? false
      argument :asset_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false

      run {Module.concat(["QuickTrain.Assets.Asset.Actions.Finalize"]), []}
    end

    action :access, QuickTrain.Assets.AssetAccessResult do
      allow_nil? false
      argument :asset_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false

      run {Module.concat(["QuickTrain.Assets.Asset.Actions.Access"]), []}
    end

    create :create_pending do
      accept [
        :id,
        :organization_id,
        :sha256,
        :byte_size,
        :media_type,
        :staging_key,
        :staging_expires_at
      ]

      change set_attribute(:state, :pending)
    end

    update :claim_operation do
      accept [:operation_claim_kind, :operation_claim_id, :operation_claim_expires_at]
      validate attribute_equals(:state, :pending)
    end

    update :claim_cleanup do
      accept [:operation_claim_kind, :operation_claim_id, :operation_claim_expires_at]
    end

    update :start_publication do
      accept [:operation_claim_expires_at, :publication_may_finish_at]
      validate attribute_equals(:state, :pending)
    end

    update :release_operation_claim do
      accept []
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    update :release_unpublished_claim do
      accept []
      validate attribute_equals(:state, :pending)
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
      change set_attribute(:publication_may_finish_at, nil)
    end

    update :complete_ready do
      accept [:sealed_key, :width, :height]
      validate attribute_equals(:state, :pending)
      change set_attribute(:state, :ready)
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    update :complete_failed do
      accept [:failure_reason]
      validate attribute_equals(:state, :pending)
      change set_attribute(:state, :failed)
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    update :complete_duplicate do
      accept [:canonical_asset_id]
      validate attribute_equals(:state, :pending)
      change set_attribute(:state, :duplicate_content)
      change set_attribute(:failure_reason, "duplicate_content")
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    update :complete_staging_cleanup do
      accept [:staging_cleaned_at]
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    update :complete_expired_staging_cleanup do
      accept [:staging_cleaned_at]
      validate attribute_equals(:state, :pending)
      change set_attribute(:state, :failed)
      change set_attribute(:failure_reason, "staging_expired")
      change set_attribute(:operation_claim_kind, nil)
      change set_attribute(:operation_claim_id, nil)
      change set_attribute(:operation_claim_expires_at, nil)
    end

    destroy :discard_registration
  end

  validations do
    validate compare(:byte_size, greater_than: 0)
    validate compare(:width, greater_than: 0)
    validate compare(:height, greater_than: 0)
  end

  policies do
    policy action(:read) do
      authorize_if accessing_from(__MODULE__, :canonical_asset)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Datasets.DatasetAssetValue"]),
                     :asset
                   )
    end

    policy action(:get_scoped) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "assets.read"}
    end

    policy action(:register) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "assets.manage"}
    end

    policy action(:finalize) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "assets.manage"}
    end

    policy action(:access) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "assets.read"}
    end
  end

  graphql do
    derive_filter? false
    type :asset
    relationships [:canonical_asset]
  end

  postgres do
    table "assets"
    repo QuickTrain.Repo

    identity_index_names staging_key: "assets_staging_key_index"

    references do
      reference :organization, on_delete: :restrict, name: "assets_organization_id_fkey"

      reference :canonical_asset,
        on_delete: :restrict,
        name: "assets_canonical_asset_id_organization_id_fkey",
        match_with: [organization_id: :organization_id]
    end

    custom_indexes do
      index [:id, :organization_id],
        unique: true,
        name: "assets_id_organization_id_index"

      index [:organization_id, :sha256],
        unique: true,
        where: "state = 'ready'",
        name: "assets_ready_organization_sha256_index"

      index [:sealed_key],
        unique: true,
        where: "sealed_key IS NOT NULL",
        name: "assets_sealed_key_index"

      index [:staging_expires_at],
        where: "staging_cleaned_at IS NULL",
        name: "assets_staging_cleanup_index"

      index [:operation_claim_expires_at],
        where: "operation_claim_id IS NOT NULL",
        name: "assets_operation_claim_expiry_index"
    end

    check_constraints do
      check_constraint :sha256, "assets_sha256_format",
        check: "octet_length(sha256) = 32",
        message: "must be exactly 32 bytes"

      check_constraint :byte_size, "assets_byte_size_positive",
        check: "byte_size > 0",
        message: "must be positive"

      check_constraint [:width, :height], "assets_image_dimensions_valid",
        check: "(width IS NULL AND height IS NULL) OR (width > 0 AND height > 0)",
        message: "must both be absent or positive"

      check_constraint :state, "assets_state_valid",
        check: "state IN ('pending', 'ready', 'failed', 'duplicate_content')",
        message: "is invalid"

      check_constraint :state, "assets_lifecycle_facts_valid",
        check: """
        (state = 'pending' AND sealed_key IS NULL AND canonical_asset_id IS NULL AND failure_reason IS NULL) OR
        (state = 'ready' AND sealed_key IS NOT NULL AND canonical_asset_id IS NULL AND failure_reason IS NULL) OR
        (state = 'failed' AND sealed_key IS NULL AND canonical_asset_id IS NULL AND failure_reason IS NOT NULL) OR
        (state = 'duplicate_content' AND sealed_key IS NULL AND canonical_asset_id IS NOT NULL AND failure_reason = 'duplicate_content')
        """,
        message: "does not match its lifecycle facts"

      check_constraint :operation_claim_kind, "assets_operation_claim_valid",
        check: """
        (operation_claim_kind IS NULL AND operation_claim_id IS NULL AND operation_claim_expires_at IS NULL) OR
        (operation_claim_kind IN ('finalize', 'cleanup') AND operation_claim_id IS NOT NULL AND operation_claim_expires_at IS NOT NULL)
        """,
        message: "must be absent or complete"
    end
  end

  identities do
    identity :staging_key, [:staging_key]
  end
end
