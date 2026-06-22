defmodule DebtStalkerWeb.Live.RoleAuthTest do
  use DebtStalkerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule AnyRoleLive do
    use DebtStalkerWeb, :live_view

    on_mount {DebtStalkerWeb.Live.RoleAuth, :any}

    @impl true
    def mount(_params, _session, socket),
      do: {:ok, Phoenix.Component.assign(socket, :page_title, "Any")}

    @impl true
    def render(assigns) do
      ~H"<p>Role: {@current_role}</p>"
    end
  end

  setup do
    original = Application.get_env(:debt_stalker, DebtStalkerWeb.Endpoint)

    on_exit(fn ->
      Application.put_env(:debt_stalker, DebtStalkerWeb.Endpoint, original)
    end)

    :ok
  end

  describe "RoleAuth :any" do
    test "allows any authenticated persona", %{conn: conn} do
      for role <- ["applicant", "admin"] do
        {:ok, _view, html} =
          live_isolated(with_role(conn, role), AnyRoleLive, session: %{"role" => role})

        assert html =~ "Role: #{role}"
      end
    end

    test "redirects when no role is set", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} =
               live_isolated(conn, AnyRoleLive, session: %{})
    end

    test "redirects unknown roles to home", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} =
               live_isolated(conn, AnyRoleLive, session: %{"role" => "unknown"})
    end
  end
end
