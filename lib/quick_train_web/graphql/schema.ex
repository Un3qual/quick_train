defmodule QuickTrainWeb.GraphQL.Schema do
  @moduledoc "The explicit public GraphQL allowlist."

  use Absinthe.Schema

  use AshGraphql,
    domains: [QuickTrain.Authentication, QuickTrain.Assets],
    define_relay_types?: true,
    relay_ids?: false

  query do
  end

  mutation do
  end
end
