defmodule QuickTrainWeb.Router do
  use QuickTrainWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :api

    forward "/graphql", Absinthe.Plug, schema: QuickTrainWeb.GraphQL.Schema
  end

  scope "/", QuickTrainWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end
end
