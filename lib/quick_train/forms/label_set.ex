defmodule QuickTrain.Forms.LabelSet do
  @moduledoc "Organization-scoped label set definition."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Forms,
    extensions: [AshGraphql.Resource],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :key, QuickTrain.Forms.PlainText,
      public?: true,
      allow_nil?: false,
      constraints: [
        trim?: false,
        allow_empty?: true,
        match: ~r/\A[^\x00]*\z/u,
        max_length: 512,
        length_count: :bytes,
        min_length: 1
      ]

    attribute :name, QuickTrain.Forms.PlainText,
      public?: true,
      constraints: [
        trim?: false,
        allow_empty?: true,
        match: ~r/\A[^\x00]*\z/u,
        max_length: 1024,
        length_count: :bytes
      ]

    timestamps()
  end

  relationships do
    belongs_to :version, QuickTrain.Forms.FormVersion, allow_nil?: false, attribute_public?: true
    has_many :labels, QuickTrain.Forms.Label, destination_attribute: :label_set_id, public?: true
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

    read :list_scoped do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(version.form.organization_id == ^arg(:organization_id))

      pagination keyset?: true,
                 required?: true,
                 default_limit: 50,
                 max_page_size: 100,
                 stable_sort: [inserted_at: :asc, id: :asc]
    end

    read :get_scoped do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and version.form.organization_id == ^arg(:organization_id))
    end

    action :add_to_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false

      argument :key, QuickTrain.Forms.PlainText,
        allow_nil?: false,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 512,
          length_count: :bytes,
          min_length: 1
        ]

      argument :name, QuickTrain.Forms.PlainText,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 1024,
          length_count: :bytes
        ]

      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :update_in_draft, :struct do
      allow_nil? false
      constraints instance_of: __MODULE__
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false

      argument :name, QuickTrain.Forms.PlainText,
        constraints: [
          trim?: false,
          allow_empty?: true,
          match: ~r/\A[^\x00]*\z/u,
          max_length: 1024,
          length_count: :bytes
        ]

      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    action :remove_from_draft, :boolean do
      allow_nil? false
      argument :organization_id, :uuid, allow_nil?: false
      argument :version_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      run {Module.concat(["QuickTrain.Forms.Authoring"]), []}
    end

    create :create_internal do
      accept [:key, :name, :version_id]
    end

    update :update_internal do
      accept [:name]
    end

    destroy :destroy_internal
  end

  policies do
    policy action(:read) do
      authorize_if {QuickTrain.Forms.NestedRead, path: [:version, :form]}
    end

    policy action(:read) do
      authorize_if accessing_from(Module.concat(["QuickTrain.Forms.FormVersion"]), :label_sets)

      authorize_if accessing_from(
                     Module.concat(["QuickTrain.Forms.AnnotationConstraints"]),
                     :label_set
                   )
    end

    policy action([:list_scoped, :get_scoped]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.read"}
    end

    policy action([:add_to_draft, :update_in_draft, :remove_from_draft]) do
      authorize_if {QuickTrain.Authorization.Checks.OrganizationCapability,
                    capability: "forms.manage"}
    end
  end

  graphql do
    type :form_label_set
    derive_filter? false
    derive_sort? false
    complexity {Module.concat(["QuickTrain.Forms"]), :connection_complexity}
    relationships [:labels]
    paginate_relationship_with labels: :relay
  end

  postgres do
    table "form_label_sets"
    repo QuickTrain.Repo

    references do
      reference :version, on_delete: :restrict
    end

    custom_indexes do
      index [:id, :version_id], unique: true
    end
  end

  identities do
    identity :parent_key, [:version_id, :key]
  end
end
