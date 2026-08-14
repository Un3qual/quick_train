defmodule QuickTrain.Organizations.Membership do
  @moduledoc "Relates a global user to an organization without changing the user's account type."

  use Ash.Resource,
    domain: QuickTrain.Organizations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "organization_memberships"
    repo QuickTrain.Repo

    unique_index_names [
      {[:organization_id, :user_id], "organization_memberships_organization_user_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, QuickTrain.Organizations.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :user, QuickTrain.Accounts.User do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :add do
      accept [:organization_id, :user_id, :status]
      upsert? true
      upsert_identity :organization_user
      upsert_fields [:status]
      return_skipped_upsert? true
    end

    update :set_status do
      accept [:status]
    end
  end

  identities do
    identity :organization_user, [:organization_id, :user_id]
  end
end
