defmodule QuickTrain.Authorization.Decision do
  @moduledoc "Optional append-only authorization decision evidence."

  use Ash.Resource,
    domain: QuickTrain.Authorization.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "authorization_decisions"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :capability, :string, allow_nil?: false, public?: true
    attribute :allowed, :boolean, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :create]
  end
end
