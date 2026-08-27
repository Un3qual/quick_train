defmodule QuickTrain.Organizations.Domain do
  @moduledoc false

  use Ash.Domain,
    otp_app: :quick_train,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain]

  graphql do
    authorize? false
    mutations do
      create QuickTrain.Organizations.Organization, :create_organization, :create
      create QuickTrain.Organizations.Membership, :add_user_to_org, :add
      update QuickTrain.Organizations.Membership, :deactivate_membership, :deactivate_membership
    end

    queries do
      read_one QuickTrain.Organizations.Membership, :user_is_member_of_org, :member?
    end

  end

  resources do
    resource QuickTrain.Organizations.Organization do
      define :create_organization, action: :create
    end
    resource QuickTrain.Organizations.Membership do
      define :member?, action: :member?
      define :add_user_to_org, action: :add
      define :deactivate_membership, action: :deactivate_membership
    end
  end
end
