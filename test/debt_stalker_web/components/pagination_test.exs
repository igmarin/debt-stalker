defmodule DebtStalkerWeb.Components.PaginationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias DebtStalkerWeb.Components.Pagination

  setup do
    Gettext.put_locale(DebtStalkerWeb.Gettext, "es")
    :ok
  end

  describe "pagination/1" do
    test "renders showing summary with correct range" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 2,
          per_page: 10,
          total_count: 25,
          total_pages: 3
        })

      assert html =~ "Mostrando"
      assert html =~ "11"
      assert html =~ "20"
      assert html =~ "25"
    end

    test "renders page navigation buttons when multiple pages" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 2,
          per_page: 10,
          total_count: 30,
          total_pages: 3
        })

      assert html =~ "phx-click"
      assert html =~ "phx-value-page"
    end

    test "disables previous button on first page" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 1,
          per_page: 10,
          total_count: 30,
          total_pages: 3
        })

      assert html =~ "disabled"
    end

    test "disables next button on last page" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 3,
          per_page: 10,
          total_count: 30,
          total_pages: 3
        })

      assert html =~ "disabled"
    end

    test "does not render nav buttons when single page" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 1,
          per_page: 10,
          total_count: 5,
          total_pages: 1
        })

      assert html =~ "Mostrando"
      refute html =~ "phx-value-page"
    end

    test "handles zero total count" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 1,
          per_page: 10,
          total_count: 0,
          total_pages: 0
        })

      # total_pages is 0, so the :if={@total_pages > 0} hides the nav
      refute html =~ "phx-value-page"
    end

    test "renders correct page range for many pages" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 5,
          per_page: 10,
          total_count: 100,
          total_pages: 10
        })

      # page_range should show pages 3-7 (page-2 to page+2)
      assert html =~ "3"
      assert html =~ "5"
      assert html =~ "7"
    end

    test "marks current page with btn-primary class" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 2,
          per_page: 10,
          total_count: 30,
          total_pages: 3
        })

      assert html =~ "btn-primary"
    end

    test "uses custom event name when provided" do
      html =
        render_component(&Pagination.pagination/1, %{
          page: 1,
          per_page: 10,
          total_count: 30,
          total_pages: 3,
          on_page: "custom_paginate"
        })

      assert html =~ "custom_paginate"
    end
  end
end
