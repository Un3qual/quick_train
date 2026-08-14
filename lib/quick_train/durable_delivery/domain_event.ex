defmodule QuickTrain.DurableDelivery.DomainEvent do
  @moduledoc "A durable, idempotent domain event ready for Oban-backed dispatch."

  use Ash.Resource,
    domain: QuickTrain.DurableDelivery.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "domain_events"
    repo QuickTrain.Repo
    identity_index_names idempotency_key: "domain_events_idempotency_key_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :topic, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "pending"
    attribute :attempts, :integer, allow_nil?: false, public?: true, default: 0
    attribute :dispatched_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :publish do
      accept [:topic, :idempotency_key, :payload]
      upsert? true
      upsert_identity :idempotency_key
      upsert_fields []
      return_skipped_upsert? true
    end

    update :mark_dispatched do
      accept [:status, :attempts, :dispatched_at]
    end
  end

  identities do
    identity :idempotency_key, [:idempotency_key]
  end
end
