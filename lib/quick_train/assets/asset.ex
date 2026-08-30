defmodule QuickTrain.Assets.Asset do
  @moduledoc "Immutable metadata and bounded lifecycle facts for one organization asset."

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Assets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :state, :string do
      allow_nil? false
      default "pending"
      public? true
    end

    attribute :sha256, :string do
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
    attribute :operation_claim_kind, :string
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
    end

    has_many :duplicate_assets, __MODULE__ do
      destination_attribute :canonical_asset_id
    end
  end

  actions do
    defaults [:read]
  end

  validations do
    validate one_of(:state, ~w(pending ready failed duplicate_content))
    validate match(:sha256, ~r/\A[0-9a-f]{64}\z/)
    validate compare(:byte_size, greater_than: 0)
    validate compare(:width, greater_than: 0)
    validate compare(:height, greater_than: 0)
    validate one_of(:operation_claim_kind, ~w(finalize cleanup))
  end

  graphql do
    type :asset
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
        check: "sha256 ~ '^[0-9a-f]{64}$'",
        message: "must be exactly 64 lowercase hexadecimal characters"

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
