defmodule QuickTrain.Accounts.Session do
  @moduledoc "An account-required session, optionally scoped to an organization."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer

  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations
  alias QuickTrain.Organizations.Organization

  postgres do
    table "sessions"
    repo QuickTrain.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :authentication_method, :string, allow_nil?: false, public?: true, default: "oidc"
    attribute :token_hash, :string, public?: true, sensitive?: true

    attribute :issued_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :user, User,
      allow_nil?: false,
      attribute_public?: true,
      filter: expr(status == "active")

    belongs_to :organization, Organization,
      allow_nil?: true,
      attribute_public?: true
  end

  actions do
    defaults [:read]

    create :issue do
      argument :user_id, :uuid, allow_nil?: false

      accept [
        :organization_id,
        :authentication_method,
        :token_hash
      ]

      change manage_relationship(:user_id, :user,
               type: :append,
               value_is_key: :id,
               authorize?: false,
               error_path: :user_id
             )

      change QuickTrain.Accounts.Session.Changes.SetTimestamps

      validate fn changeset, _context ->
        organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
        user_id = Ash.Changeset.get_argument(changeset, :user_id)

        if is_nil(organization_id) or Organizations.member?(organization_id, user_id) do
          :ok
        else
          {:error, field: :organization_id, message: "active membership required"}
        end
      end
    end

    update :revoke do
      accept [:revoked_at]
    end
  end
end
