defmodule QuickTrainWeb.GraphqlApiTest do
  use QuickTrain.ConnCase, async: true

  test "serves the GraphQL API", %{conn: conn} do
    conn = post(conn, "/graphql", %{query: "{ health }"})

    assert json_response(conn, 200) == %{"data" => %{"health" => "ok"}}
  end

  test "does not expose a generated REST API", %{conn: conn} do
    conn = get(conn, "/api/v1/users")
    assert response(conn, 404)
  end

  test "serves a minimal operational health check", %{conn: conn} do
    conn = get(conn, "/healthz")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
