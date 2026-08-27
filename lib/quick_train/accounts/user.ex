defmodule QuickTrain.Accounts.User do
  @moduledoc "A global human account; organization access is modeled separately."

  use Ash.Resource,
    domain: QuickTrain.Accounts.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource]

  alias QuickTrain.Accounts.{AuthenticationEvent, Session}
  alias QuickTrain.Authorization.{Role}
  alias QuickTrain.EnterpriseIdentity.{EnterpriseConnection, DirectoryGroup, DirectoryMembership, DirectoryUser}
  alias QuickTrain.Organizations.{Organization, Membership}

  postgres do
    table "users"
    repo QuickTrain.Repo
    identity_index_names email: "users_email_index"
  end

  graphql do
    type :user
    paginate_relationship_with [directory_groups: :relay]
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

    has_many :directory_memberships, DirectoryMembership, destination_attribute: :directory_user_id, public?: true

    many_to_many :enterprise_connections, EnterpriseConnection,
      through: DirectoryUser, public?: true

    has_many :directory_groups, DirectoryGroup,
      through: [:directory_memberships, :directory_group], public?: true

  end


  actions do
    defaults [:read]

    read :list_active do
      pagination required?: false, offset?: false, keyset?: true
      filter expr(status == "active")
    end

    create :register do
      accept [:email, :display_name, :status]
      return_skipped_upsert? true
      validate one_of(:status, ~w(active disabled))
      change set_attribute(:display_name, &String.trim/1)
      change set_attribute(:email, &__MODULE__.normalize_email/1)
    end

    update :set_status do
      accept [:status]
      validate one_of(:status, ~w(active disabled))
    end
  end

  identities do
    identity :email, [:email]
  end

  def normalize_email(email) do
    email |> String.trim() |> String.downcase()
  end
end
