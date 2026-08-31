defmodule QuickTrain.Datasets.DatasetImport do
  @moduledoc "Bounded idempotent import pinned to one published dataset schema."

  alias QuickTrain.Accounts.User
  alias QuickTrain.Datasets.{Dataset, DatasetImportRow, DatasetSchemaVersion}
  alias QuickTrain.Datasets.DatasetImport.Lifecycle
  alias QuickTrain.Organizations.Organization

  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Datasets,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :open_fingerprint, QuickTrain.Types.Sha256Digest, allow_nil?: false

    attribute :phase, QuickTrain.Datasets.DatasetImport.Phase,
      allow_nil?: false,
      default: :open,
      public?: true

    attribute :open_expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :sealed_at, :utc_datetime_usec, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :dataset, Dataset,
      allow_nil?: false,
      public?: true

    belongs_to :schema_version, DatasetSchemaVersion,
      allow_nil?: false,
      public?: true

    belongs_to :initiated_by, User,
      allow_nil?: false,
      attribute_public?: true

    has_many :rows, DatasetImportRow,
      destination_attribute: :import_id,
      public?: true
  end

  aggregates do
    count :row_count, :rows do
      public? true
      authorize? false
    end

    count :pending, :rows do
      filter expr(outcome == :pending)
      public? true
      authorize? false
    end

    count :succeeded, :rows do
      filter expr(outcome == :succeeded)
      public? true
      authorize? false
    end

    count :unchanged, :rows do
      filter expr(outcome == :unchanged)
      public? true
      authorize? false
    end

    count :failed, :rows do
      filter expr(outcome == :failed)
      public? true
      authorize? false
    end
  end

  calculations do
    calculate :import_id, :uuid, expr(id) do
      public? true
    end

    calculate :lifecycle,
              Lifecycle,
              expr(
                cond do
                  phase == :open -> :open
                  pending > 0 -> :pending
                  row_count == 0 -> :completed
                  failed == row_count -> :failed
                  failed > 0 -> :partially_failed
                  true -> :completed
                end
              ) do
      public? true
    end
  end

  actions do
    defaults [:read]

    action :open, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      argument :schema_version_id, :uuid, allow_nil?: false
      argument :idempotency_key, :string, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetImport.Actions.Open"]), []}
    end

    action :finalize, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :import_id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Datasets.DatasetImport.Actions.Finalize"]), []}
    end

    read :inspect do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :import_id, :uuid, allow_nil?: false

      filter expr(id == ^arg(:import_id) and organization_id == ^arg(:organization_id))

      prepare build(
                load: [
                  :import_id,
                  :lifecycle,
                  :row_count,
                  :pending,
                  :succeeded,
                  :unchanged,
                  :failed
                ]
              )
    end

    create :create_internal do
      accept [
        :organization_id,
        :dataset_id,
        :schema_version_id,
        :initiated_by_id,
        :idempotency_key,
        :open_fingerprint,
        :open_expires_at
      ]

      change set_attribute(:phase, :open)
    end

    update :seal_internal do
      accept [:sealed_at]
      validate attribute_equals(:phase, :open)
      change set_attribute(:phase, :sealed)
    end

    destroy :destroy_internal
  end

  policies do
    policy action([:open, :finalize, :inspect]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "dataset_imports.manage"}
    end
  end

  graphql do
    derive_filter? false
    derive_sort? false
    type :dataset_import
    relationships [:dataset, :schema_version, :rows]
    paginate_relationship_with rows: :relay
  end

  postgres do
    table "dataset_imports"
    repo QuickTrain.Repo

    identity_index_names organization_dataset_key:
                           "dataset_imports_organization_dataset_key_index"

    references do
      reference :organization, on_delete: :restrict, name: "dataset_imports_organization_id_fkey"

      reference :dataset,
        on_delete: :restrict,
        name: "dataset_imports_dataset_scope_fkey",
        match_with: [organization_id: :organization_id]

      reference :schema_version,
        on_delete: :restrict,
        name: "dataset_imports_schema_scope_fkey",
        match_with: [dataset_id: :dataset_id]

      reference :initiated_by, on_delete: :restrict, name: "dataset_imports_initiated_by_id_fkey"
    end

    custom_indexes do
      index [:id, :organization_id, :dataset_id, :schema_version_id],
        unique: true,
        name: "dataset_imports_id_full_scope_index"

      index [:phase, :open_expires_at, :id], name: "dataset_imports_expiry_cursor_index"
    end

    check_constraints do
      check_constraint :phase, "dataset_imports_phase_valid",
        check: "phase IN ('open', 'sealed')",
        message: "is invalid"

      check_constraint :phase, "dataset_imports_phase_facts_valid",
        check:
          "(phase = 'open' AND sealed_at IS NULL) OR (phase = 'sealed' AND sealed_at IS NOT NULL)",
        message: "does not match lifecycle facts"

      check_constraint :open_fingerprint, "dataset_imports_open_fingerprint_format",
        check: "octet_length(open_fingerprint) = 32",
        message: "must be exactly 32 bytes"
    end
  end

  identities do
    identity :organization_dataset_key, [:organization_id, :dataset_id, :idempotency_key]
  end
end
