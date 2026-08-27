defmodule QuickTrain.Organizations do
  @moduledoc "Enterprise organizations and user memberships."

  use Ash.Domain,
    otp_app: :quick_train,
    extensions: [AshGraphql.Domain]

  alias QuickTrain.Organizations.{Membership, Organization}

  graphql do
    authorize? false

    mutations do
      create Organization, :create_organization, :create
      create Membership, :add_user_to_org, :add
      update Membership, :deactivate_membership, :deactivate
    end

    queries do
      action Membership, :user_is_member_of_org, :member?
    end
  end

  resources do
    resource Organization do
      define :create_organization, action: :create, args: [:name, :slug]
    end

    resource Membership do
      define :member?, action: :member?, args: [:organization_id, :user_id]
      define :add_member, action: :add, args: [:organization_id, :user_id]
      define :deactivate_membership, action: :deactivate
    end
  end
end
