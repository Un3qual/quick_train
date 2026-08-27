defmodule QuickTrain.Accounts.ExternalIdentity do
  @moduledoc "Links an OIDC provider subject to a global user account."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_identities"
    repo QuickTrain.Repo

    unique_index_names [
      {[:provider, :subject], "external_identities_provider_subject_index"},
      {[:user_id, :provider], "external_identities_user_provider_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :claims, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :user, QuickTrain.Accounts.User do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :link do
      accept [:user_id, :provider, :subject, :status, :claims]
      upsert? true
      upsert_identity :provider_subject
      upsert_fields [:user_id, :status, :claims]
      return_skipped_upsert? true
    end

    update :refresh do
      accept [:status, :claims]
    end
  end

  identities do
    identity :provider_subject, [:provider, :subject]
    identity :user_provider, [:user_id, :provider]
  end
end
