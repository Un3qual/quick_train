defmodule QuickTrain.Audit.Record do
  @moduledoc "Append-only audit evidence for business and administrative changes."

  use Ash.Resource,
    domain: QuickTrain.Audit.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "audit_records"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :subject_type, :string, allow_nil?: false, public?: true
    attribute :subject_id, :uuid, allow_nil?: false, public?: true
    attribute :actor_user_id, :uuid, public?: true
    attribute :organization_id, :uuid, public?: true
    attribute :metadata, :map, allow_nil?: false, public?: true, default: %{}
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:action, :subject_type, :subject_id, :actor_user_id, :organization_id, :metadata]
    end
  end
end
