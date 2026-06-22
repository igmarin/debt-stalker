defmodule DebtStalkerWeb.Components.UITest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias DebtStalkerWeb.Components.UI

  setup do
    Gettext.put_locale(DebtStalkerWeb.Gettext, "es")
    :ok
  end

  describe "status_badge/1" do
    test "renders a formatted status with semantic color" do
      html = render_component(&UI.status_badge/1, %{status: "approved"})

      assert html =~ "Aprobada"
      assert html =~ "badge-success"
    end
  end

  describe "empty_state/1" do
    test "renders title and description" do
      html =
        render_component(&UI.empty_state/1, %{
          title: "Nothing here",
          description: "Try again later."
        })

      assert html =~ "Nothing here"
      assert html =~ "Try again later."
    end
  end

  describe "audit_timeline/1" do
    test "renders audit entries" do
      entry = %{
        action: "status_changed",
        actor: "admin",
        metadata: %{"from" => "submitted", "to" => "pending_risk"},
        inserted_at: ~U[2026-01-15 10:00:00Z]
      }

      html = render_component(&UI.audit_timeline/1, %{entries: [entry]})

      assert html =~ "Estado cambiado"
      assert html =~ "admin"
      assert html =~ "Enviada"
      assert html =~ "Riesgo pendiente"
    end

    test "renders naive datetime timestamps" do
      entry = %{
        action: "created",
        actor: "system",
        metadata: %{},
        inserted_at: ~N[2026-01-15 10:00:00]
      }

      html = render_component(&UI.audit_timeline/1, %{entries: [entry]})

      assert html =~ "2026-01-15 10:00:00"
    end
  end

  describe "stat_card/1" do
    test "renders title, value, and optional description" do
      html =
        render_component(&UI.stat_card/1, %{
          title: "Total",
          value: 42,
          description: "All time",
          icon: "hero-document-text"
        })

      assert html =~ "Total"
      assert html =~ "42"
      assert html =~ "All time"
    end
  end

  describe "status_options/0" do
    test "returns formatted status labels" do
      options = UI.status_options()

      assert {"Enviada", "submitted"} in options
      assert {"Aprobada", "approved"} in options
    end
  end

  describe "format_status/1" do
    test "formats atoms and strings" do
      assert UI.format_status(:pending_risk) == "Riesgo pendiente"
      assert UI.format_status("additional_review") == "Revisión adicional"
      assert UI.format_status(nil) == ""
    end
  end
end
