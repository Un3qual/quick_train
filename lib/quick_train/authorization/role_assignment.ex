defmodule QuickTrain.Authorization.RoleAssignment do
  @moduledoc "Assigns an organization role to a user."

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "role_assignments"
    repo QuickTrain.Repo

    unique_index_names [
      {[:organization_id, :user_id, :role_id], "role_assignments_organization_user_role_index"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    attribute :role_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]

    create :assign do
      accept [:organization_id, :user_id, :role_id]
      upsert? true
      upsert_identity :organization_user_role
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :organization_user_role, [:organization_id, :user_id, :role_id]
  end
end
