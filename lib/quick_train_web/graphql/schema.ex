defmodule QuickTrainWeb.GraphQL.Schema do
  @moduledoc "The explicit public GraphQL allowlist."

  use Absinthe.Schema

  alias QuickTrainWeb.GraphQL.AuthenticationResolver

  object :oidc_begin_payload do
    field :authorization_uri, non_null(:string)
    field :state, non_null(:string)
    field :client_proof, non_null(:string)
    field :expires_at, non_null(:string)
  end

  object :oidc_exchange_payload do
    field :token, non_null(:string)
    field :session_id, non_null(:id)
    field :expires_at, non_null(:string)
  end

  query do
    field :begin_oidc_login, non_null(:oidc_begin_payload) do
      arg(:callback_key, non_null(:string))
      resolve(&AuthenticationResolver.begin_oidc_login/3)
    end
  end

  mutation do
    field :exchange_oidc_login, non_null(:oidc_exchange_payload) do
      arg(:code, non_null(:string))
      arg(:state, non_null(:string))
      arg(:client_proof, non_null(:string))
      resolve(&AuthenticationResolver.exchange_oidc_login/3)
    end
  end
end
