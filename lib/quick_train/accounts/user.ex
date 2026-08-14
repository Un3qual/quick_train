defmodule QuickTrain.Accounts.User do
  @moduledoc "A global human account; organization access is modeled separately."

  use Ash.Resource,
    domain: QuickTrain.Accounts.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo QuickTrain.Repo
    identity_index_names email: "users_email_index"
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :register do
      accept [:email, :display_name, :status]
      upsert? true
      upsert_identity :email
      upsert_fields [:display_name]
      return_skipped_upsert? true
      validate one_of(:status, ~w(active disabled))
    end

    update :set_status do
      accept [:status]
      validate one_of(:status, ~w(active disabled))
    end
  end

  identities do
    identity :email, [:email]
  end
end
