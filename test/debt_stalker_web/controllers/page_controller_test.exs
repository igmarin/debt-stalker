defmodule DebtStalkerWeb.PageControllerTest do
  use DebtStalkerWeb.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Debt Stalker"
    assert html_response(conn, 200) =~ "Apply for credit"
    assert html_response(conn, 200) =~ "Admin review"
  end

  test "POST /set-role redirects applicants to the form", %{conn: conn} do
    conn = post(conn, ~p"/set-role", %{"role" => "applicant"})
    assert redirected_to(conn) == "/apply"
  end

  test "POST /set-role does not allow admin role without login", %{conn: conn} do
    conn = post(conn, ~p"/set-role", %{"role" => "admin"})
    assert redirected_to(conn) == "/"
  end

  test "POST /set-role with invalid role redirects home", %{conn: conn} do
    conn = post(conn, ~p"/set-role", %{"role" => "unknown"})
    assert redirected_to(conn) == "/"
  end

  test "GET /admin/login renders the login form", %{conn: conn} do
    conn = get(conn, ~p"/admin/login")
    assert html_response(conn, 200) =~ "Admin sign in"
  end

  test "POST /admin/login with valid password sets admin role", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{"password" => "admin123"})
    assert redirected_to(conn) == "/admin"
    assert get_session(conn, "role") == "admin"
  end

  test "POST /admin/login with invalid password shows an error", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{"password" => "wrong"})
    assert html_response(conn, 200) =~ "Invalid password"
    refute get_session(conn, "role")
  end

  test "DELETE /admin/logout clears the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"role" => "admin"})
      |> delete(~p"/admin/logout")

    assert redirected_to(conn) == "/"

    # After recycling the connection, the admin area should require login again.
    conn =
      conn
      |> recycle()
      |> get(~p"/admin")

    assert redirected_to(conn) == "/admin/login"
  end

  test "legacy /applications redirects to the admin list", %{conn: conn} do
    conn = get(conn, ~p"/applications")
    assert redirected_to(conn) == "/admin/applications"
  end

  test "legacy /applications/new redirects to the applicant form", %{conn: conn} do
    conn = get(conn, ~p"/applications/new")
    assert redirected_to(conn) == "/apply"
  end

  test "legacy /applications/:id redirects to the admin detail page", %{conn: conn} do
    id = Ecto.UUID.generate()
    conn = get(conn, ~p"/applications/#{id}")
    assert redirected_to(conn) == "/admin/applications/#{id}"
  end
end
