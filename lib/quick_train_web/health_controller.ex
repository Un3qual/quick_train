defmodule QuickTrainWeb.HealthController do
  @moduledoc false
  use QuickTrainWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
