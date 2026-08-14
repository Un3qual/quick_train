defmodule QuickTrain.Authorization.Role do
  @moduledoc "An organization-scoped collection of capabilities."

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "roles"
    repo QuickTrain.Repo
    unique_index_names [{[:organization_id, :key], "roles_organization_key_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:organization_id, :key, :name]
      upsert? true
      upsert_identity :organization_key
      upsert_fields [:name]
      return_skipped_upsert? true
    end
  end

  identities do
    identity :organization_key, [:organization_id, :key]
  end
end
