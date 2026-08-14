defmodule QuickTrain.Authorization.RoleCapability do
  @moduledoc false

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "role_capabilities"
    repo QuickTrain.Repo
    unique_index_names [{[:role_id, :capability_id], "role_capabilities_role_capability_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :role_id, :uuid, allow_nil?: false, public?: true
    attribute :capability_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]

    create :grant do
      accept [:role_id, :capability_id]
      upsert? true
      upsert_identity :role_capability
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :role_capability, [:role_id, :capability_id]
  end
end
