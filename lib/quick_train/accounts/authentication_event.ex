defmodule QuickTrain.Accounts.AuthenticationEvent do
  @moduledoc "Append-only authentication telemetry without credentials or tokens."

  use Ash.Resource,
    domain: QuickTrain.Accounts.Domain,
    data_layer: AshPostgres.DataLayer

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.Organization

  postgres do
    table "authentication_events"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :event, :string, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true
    attribute :reason, :string, public?: true
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :user, User,
      allow_nil?: true,
      attribute_public?: true
    belongs_to :organization, Organization,
      allow_nil?: true,
      attribute_public?: true
  end

  actions do
    defaults [:read, :create]
  end
end
