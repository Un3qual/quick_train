defmodule QuickTrain.Accounts.User do
  @moduledoc "A global human account; organization access is modeled separately."

  use Ash.Resource,
    domain: QuickTrain.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.AuthenticationEvent

  alias QuickTrain.EnterpriseIdentity.{
    DirectoryGroup,
    DirectoryMembership,
    DirectoryUser,
    EnterpriseConnection
  }

  alias QuickTrain.Organizations.{Membership, Organization}

  postgres do
    table "users"
    repo QuickTrain.Repo
    identity_index_names email: "users_email_index"
  end

  graphql do
    type :user
    paginate_relationship_with directory_groups: :relay
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true, default: "active"

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :authentication_events, AuthenticationEvent, public?: true
    many_to_many :organizations, Organization, through: Membership, public?: true

    has_many :directory_users, DirectoryUser, public?: true

    has_many :directory_memberships, DirectoryMembership,
      through: [:directory_users, :directory_memberships],
      public?: true

    many_to_many :enterprise_connections, EnterpriseConnection,
      through: DirectoryUser,
      public?: true

    has_many :directory_groups, DirectoryGroup,
      through: [:directory_users, :directory_groups],
      public?: true
  end

  actions do
    defaults [:read]

    read :list_active do
      pagination required?: false, offset?: false, keyset?: true
      filter expr(status == "active")
    end

    create :register do
      accept [:email, :display_name, :status]
      upsert? true
      upsert_identity :email
      upsert_fields [:display_name]
      return_skipped_upsert? true
      validate one_of(:status, ~w(active disabled))
      change update_change(:display_name, &String.trim/1)

      change update_change(:email, fn email ->
               email |> String.trim() |> String.downcase()
             end)
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
