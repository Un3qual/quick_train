defmodule QuickTrainWeb.Router do
  use QuickTrainWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug AshGraphql.Plug
  end

  scope "/" do
    pipe_through :api

    forward "/graphql", Absinthe.Plug, schema: QuickTrainWeb.GraphQL.Schema

    if Mix.env() == :dev do
      forward "/graphiql",
              Absinthe.Plug.GraphiQL,
              schema: QuickTrainWeb.GraphQL.Schema,
              interface: :simple
    end
  end

  scope "/", QuickTrainWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end
end
