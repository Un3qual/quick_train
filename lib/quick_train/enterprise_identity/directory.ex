defmodule QuickTrain.EnterpriseIdentity.Directory do
  @moduledoc "A directory synchronized through an enterprise connection."

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "directories"
    repo QuickTrain.Repo
    unique_index_names [{[:connection_id, :external_id], "directories_connection_external_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :connection_id, :uuid, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    attribute :last_synced_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :create, :update]
  end

  identities do
    identity :connection_external, [:connection_id, :external_id]
  end
end
