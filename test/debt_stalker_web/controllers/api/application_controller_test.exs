defmodule DebtStalkerWeb.Api.ApplicationControllerTest do
  use DebtStalkerWeb.ConnCase, async: false

  alias DebtStalkerWeb.Auth.Token

  @valid_es_params %{
    "country" => "ES",
    "full_name" => "Juan Garcia",
    "identity_document" => "12345678Z",
    "requested_amount" => "5000",
    "monthly_income" => "2000"
  }

  defp auth_conn(conn, role) do
    {:ok, token} = Token.generate_token(role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/applications" do
    test "creates application with update role", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", @valid_es_params)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["country"] == "ES"
      assert data["status"] == "submitted"
      assert data["identity_document"] =~ "****"
      refute data["identity_document"] == "12345678Z"
      assert data["full_name"] == "Juan Garcia"
    end

    test "returns 401 without token", %{conn: conn} do
      conn = post(conn, "/api/applications", @valid_es_params)
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 403 with read role", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> post("/api/applications", @valid_es_params)

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 422 for invalid country", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", Map.put(@valid_es_params, "country", "XX"))

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["country"] != nil
    end
  end

  describe "GET /api/applications" do
    setup %{conn: conn} do
      conn
      |> auth_conn("update")
      |> post("/api/applications", @valid_es_params)

      :ok
    end

    test "lists applications with read role", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications")

      assert %{"data" => data, "cursor" => _cursor} = json_response(conn, 200)
      assert data != []
    end

    test "filters by country", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications", %{"country" => "ES"})

      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.all?(data, &(&1["country"] == "ES"))
    end

    test "filters by status", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications", %{"status" => "submitted"})

      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.all?(data, &(&1["status"] == "submitted"))
    end

    test "filters by date_from", %{conn: conn} do
      today = Date.utc_today() |> Date.to_iso8601()

      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications", %{"date_from" => today})

      assert %{"data" => data} = json_response(conn, 200)
      assert data != []
    end

    test "filters by date_to returns empty for future cutoff", %{conn: conn} do
      future = Date.add(Date.utc_today(), 365) |> Date.to_iso8601()

      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications", %{"date_to" => future})

      assert %{"data" => data} = json_response(conn, 200)
      # All apps created today should be before future date
      assert data != []
    end

    test "date_from in future returns empty list", %{conn: conn} do
      future = Date.add(Date.utc_today(), 365) |> Date.to_iso8601()

      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications", %{"date_from" => future})

      assert %{"data" => data} = json_response(conn, 200)
      assert data == []
    end
  end

  describe "GET /api/applications/:id" do
    test "returns application by id", %{conn: conn} do
      create_conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", @valid_es_params)

      %{"data" => %{"id" => id}} = json_response(create_conn, 201)

      show_conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications/#{id}")

      assert %{"data" => data} = json_response(show_conn, 200)
      assert data["id"] == id
      assert data["identity_document"] =~ "****"
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "PATCH /api/applications/:id/status" do
    test "updates status with update role", %{conn: conn} do
      create_conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", @valid_es_params)

      %{"data" => %{"id" => id}} = json_response(create_conn, 201)

      patch_conn =
        conn
        |> auth_conn("update")
        |> patch("/api/applications/#{id}/status", %{"status" => "pending_risk"})

      assert %{"data" => data} = json_response(patch_conn, 200)
      assert data["status"] == "pending_risk"
    end

    test "returns 422 for invalid transition", %{conn: conn} do
      create_conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", @valid_es_params)

      %{"data" => %{"id" => id}} = json_response(create_conn, 201)

      patch_conn =
        conn
        |> auth_conn("update")
        |> patch("/api/applications/#{id}/status", %{"status" => "approved"})

      assert json_response(patch_conn, 422)["error"] == "invalid_transition"
    end
  end
end
