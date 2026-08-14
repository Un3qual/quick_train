defmodule QuickTrain.EnterpriseIdentity.DirectoryGroup do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "directory_groups"
    repo QuickTrain.Repo

    unique_index_names [
      {[:directory_id, :external_id], "directory_groups_directory_external_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :directory_id, :uuid, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :create, :update]
  end

  identities do
    identity :directory_external, [:directory_id, :external_id]
  end
end
