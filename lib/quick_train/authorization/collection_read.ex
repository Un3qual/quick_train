defmodule QuickTrain.Authorization.CollectionRead do
  @moduledoc "A scoped collection read shared by canonical form and field definitions."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  actions do
    read :get_collection_definition do
      transaction? true
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :attempt_id, :uuid
      filter expr(id == ^arg(:id))
      prepare Module.concat(["QuickTrain.Authorization.CollectionRead.Scope"])
    end
  end

  policies do
    policy action(:get_collection_definition) do
      authorize_if Module.concat(["QuickTrain.Authorization.Checks.CollectionContext"])
    end
  end
end
