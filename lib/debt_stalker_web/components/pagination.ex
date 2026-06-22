defmodule DebtStalkerWeb.Components.Pagination do
  @moduledoc """
  Page-based pagination controls for admin tables.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  import DebtStalkerWeb.CoreComponents, only: [icon: 1]

  @doc "Renders pagination controls with prev/next and page summary."
  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total_count, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :on_page, :string, default: "paginate"
  attr :class, :any, default: nil

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    assigns =
      assign(assigns, :range, page_range(assigns.page, assigns.total_pages))

    ~H"""
    <nav
      :if={@total_pages > 0}
      class={["flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between", @class]}
    >
      <p class="text-sm text-base-content/70">
        {gettext("Showing %{from}–%{to} of %{total}",
          from: range_start(@page, @per_page, @total_count),
          to: range_end(@page, @per_page, @total_count),
          total: @total_count
        )}
      </p>

      <div :if={@total_pages > 1} class="join">
        <button
          type="button"
          class="join-item btn btn-sm"
          phx-click={@on_page}
          phx-value-page={max(@page - 1, 1)}
          disabled={@page <= 1}
          aria-label={gettext("Previous page")}
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>

        <%= for page_number <- @range do %>
          <%= if page_number == :ellipsis do %>
            <span class="join-item btn btn-sm btn-disabled">…</span>
          <% else %>
            <button
              type="button"
              class={["join-item btn btn-sm", page_number == @page && "btn-primary"]}
              phx-click={@on_page}
              phx-value-page={page_number}
              aria-current={page_number == @page && "page"}
            >
              {page_number}
            </button>
          <% end %>
        <% end %>

        <button
          type="button"
          class="join-item btn btn-sm"
          phx-click={@on_page}
          phx-value-page={min(@page + 1, @total_pages)}
          disabled={@page >= @total_pages}
          aria-label={gettext("Next page")}
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </div>
    </nav>
    """
  end

  defp range_start(_page, _per_page, 0), do: 0
  defp range_start(page, per_page, _total), do: (page - 1) * per_page + 1

  defp range_end(_page, _per_page, 0), do: 0
  defp range_end(page, per_page, total), do: min(page * per_page, total)

  defp page_range(_page, total_pages) when total_pages <= 0, do: []

  defp page_range(_page, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..total_pages)

  defp page_range(page, total_pages) do
    start_page = max(page - 2, 1)
    end_page = min(page + 2, total_pages)
    Enum.to_list(start_page..end_page)
  end
end
