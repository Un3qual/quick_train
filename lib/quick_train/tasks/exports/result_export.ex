defmodule QuickTrain.Tasks.Exports.ResultExport do
  @moduledoc "Scoped collection result export evidence."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :state, :atom,
      public?: true,
      allow_nil?: false,
      default: :queued,
      constraints: [one_of: [:queued, :snapshotting, :writing, :ready, :failed]]

    attribute :mode, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:accepted, :audit]]

    attribute :request_key, :uuid, public?: true, allow_nil?: false
    attribute :snapshot_at, :utc_datetime_usec, public?: true, allow_nil?: true
    attribute :record_count, :integer, public?: true, allow_nil?: true, constraints: [min: 0]
    attribute :error_code, :string, public?: true, allow_nil?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false, attribute_public?: true

    belongs_to :form_version, QuickTrain.Forms.FormVersion,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :requester, QuickTrain.Accounts.User, allow_nil?: false, attribute_public?: true
    belongs_to :asset, QuickTrain.Assets.Asset, allow_nil?: true, attribute_public?: true
    belongs_to :pending_asset, QuickTrain.Assets.Asset, allow_nil?: true
  end

  actions do
    action :process do
      public? false
      argument :id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Exports.ResultExporting"])
    end

    action :seal_snapshot, :struct do
      public? false
      constraints instance_of: __MODULE__
      argument :id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Exports.Snapshot"])
    end

    action :request_export, :struct do
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :request_key, :uuid, allow_nil?: false
      argument :mode, :atom, allow_nil?: false, constraints: [one_of: [:accepted, :audit]]
      run Module.concat(["QuickTrain.Tasks.Exports.ResultExporting"])
    end

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and project_id == ^arg(:project_id))

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :export_id, :uuid, allow_nil?: false

      filter expr(
               id == ^arg(:export_id) and organization_id == ^arg(:organization_id) and
                 project_id == ^arg(:project_id)
             )
    end

    action :download_export, QuickTrain.Assets.AssetAccessResult do
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :export_id, :uuid, allow_nil?: false
      run Module.concat(["QuickTrain.Tasks.Exports.ResultExporting"])
    end

    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    create :create_internal do
      accept [
        :state,
        :mode,
        :request_key,
        :snapshot_at,
        :record_count,
        :error_code,
        :organization_id,
        :project_id,
        :form_version_id,
        :requester_id,
        :asset_id,
        :pending_asset_id
      ]
    end

    update :update_internal do
      accept [
        :state,
        :snapshot_at,
        :record_count,
        :error_code,
        :asset_id,
        :pending_asset_id
      ]
    end
  end

  policies do
    policy action([:request_export, :list_scoped, :get_scoped, :download_export]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "tasks.results.read"}
    end

    policy action([:read, :create_internal, :update_internal]) do
      forbid_if always()
    end
  end

  graphql do
    attribute_types record_count: :string
    type :result_export
    derive_filter? false
    derive_sort? false
    relationships []
  end

  postgres do
    table "result_exports"
    repo QuickTrain.Repo
    migration_types record_count: :bigint

    references do
      reference :organization,
        on_delete: :restrict,
        name: "result_exports_organization_scope_fkey"

      reference :project,
        on_delete: :restrict,
        name: "result_exports_project_scope_fkey",
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version,
        on_delete: :restrict,
        name: "result_exports_form_version_scope_fkey"

      reference :requester, on_delete: :restrict, name: "result_exports_requester_scope_fkey"

      reference :asset,
        on_delete: :restrict,
        name: "result_exports_asset_scope_fkey",
        match_with: [organization_id: :organization_id]

      reference :pending_asset,
        on_delete: :restrict,
        match_with: [organization_id: :organization_id]
    end

    custom_indexes do
      index [:id, :organization_id, :project_id, :form_version_id], unique: true
      index [:id, :organization_id], unique: true
    end
  end

  identities do
    identity :request, [:project_id, :requester_id, :request_key]
  end
end
