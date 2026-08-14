defmodule QuickTrainWeb.Router do
  use QuickTrainWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end
end
