defmodule QuickTrainWeb.GraphQL.Schema do
  @moduledoc "The single application API surface; extend this schema with product domains."

  use Absinthe.Schema

  use AshGraphql,
    domains: [QuickTrain.Organizations.Domain, QuickTrain.Accounts.Domain, QuickTrain.EnterpriseIdentity.Domain, QuickTrain.Authorization.Domain],
    relay_ids?: true

  query do
    # field :health, non_null(:string) do
    #   resolve(fn _parent, _args, _resolution -> {:ok, "ok"} end)
    # end
  end

  mutation do

  end

end
