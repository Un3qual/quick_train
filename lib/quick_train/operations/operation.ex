defmodule QuickTrain.Operations.Operation do
  @moduledoc "Correlates an idempotent user or system operation across boundaries."

  use Ash.Resource,
    domain: QuickTrain.Operations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "operations"
    repo QuickTrain.Repo
    unique_index_names [{[:source, :idempotency_key], "operations_source_idempotency_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :source, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :operation, :string, allow_nil?: false, public?: true
    attribute :user_id, :uuid, public?: true
    attribute :organization_id, :uuid, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "started"
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :start do
      accept [
        :source,
        :idempotency_key,
        :operation,
        :user_id,
        :organization_id,
        :status,
        :metadata
      ]

      upsert? true
      upsert_identity :source_idempotency
      upsert_fields []
      return_skipped_upsert? true
    end

    update :finish do
      accept [:status, :metadata]
    end
  end

  identities do
    identity :source_idempotency, [:source, :idempotency_key]
  end
end
