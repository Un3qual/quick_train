defmodule QuickTrain.EnterpriseIdentity.DirectoryUser do
  @moduledoc "Links a provider directory user to a global user and enterprise membership."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "directory_users"
    repo QuickTrain.Repo

    unique_index_names [
      {[:connection_id, :external_id], "directory_users_connection_external_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :connection_id, :uuid, allow_nil?: false, public?: true
    attribute :membership_id, :uuid, allow_nil?: false, public?: true
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :profile, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :link do
      accept [:connection_id, :membership_id, :user_id, :external_id, :status, :profile]
      upsert? true
      upsert_identity :connection_external
      upsert_fields [:membership_id, :user_id, :status, :profile]
      return_skipped_upsert? true
    end

    update :set_status do
      accept [:status]
    end
  end

  identities do
    identity :connection_external, [:connection_id, :external_id]
  end
end
