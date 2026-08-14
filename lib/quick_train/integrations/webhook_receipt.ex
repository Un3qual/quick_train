defmodule QuickTrain.Integrations.WebhookReceipt do
  @moduledoc "Deduplicates inbound provider webhooks while retaining their original payload."

  use Ash.Resource,
    domain: QuickTrain.Integrations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "webhook_receipts"
    repo QuickTrain.Repo
    unique_index_names [{[:provider, :external_id], "webhook_receipts_provider_external_index"}]
  end

  attributes do
    uuid_primary_key :id
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :external_id, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "received"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :record do
      accept [:provider, :external_id, :payload]
      upsert? true
      upsert_identity :provider_external
      upsert_fields []
      return_skipped_upsert? true
    end
  end

  identities do
    identity :provider_external, [:provider, :external_id]
  end
end
