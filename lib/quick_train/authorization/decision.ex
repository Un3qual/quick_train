defmodule QuickTrain.Authorization.Decision do
  @moduledoc "Optional append-only authorization decision evidence."

  use Ash.Resource,
    domain: QuickTrain.Authorization,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.Organization

  postgres do
    table "authorization_decisions"
    repo QuickTrain.Repo
  end

  graphql do
    type :decision
  end

  attributes do
    uuid_primary_key :id

    attribute :capability, :string, allow_nil?: false, public?: true
    attribute :allowed, :boolean, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :user, User,
      allow_nil?: false,
      attribute_public?: true

    belongs_to :organization, Organization,
      allow_nil?: false,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :record do
      accept [:user_id, :organization_id, :capability, :allowed, :reason, :metadata]
    end
  end
end
