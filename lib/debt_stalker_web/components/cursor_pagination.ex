defmodule DebtStalkerWeb.Components.CursorPagination do
  @moduledoc """
  Cursor-based pagination controls for admin tables.

  Shows a "Load more" button while a cursor is present and a summary of the
  number of entries currently displayed.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  import DebtStalkerWeb.CoreComponents, only: [icon: 1]

  @doc "Renders cursor pagination controls."
  attr :cursor, :string, required: true
  attr :displayed_count, :integer, required: true
  attr :on_load_more, :string, default: "load_more"
  attr :class, :any, default: nil

  @spec cursor_pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def cursor_pagination(assigns) do
    ~H"""
    <nav class={["flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between", @class]}>
      <p class="text-sm text-base-content/70">
        {gettext("Showing %{count} applications", count: @displayed_count)}
      </p>

      <button
        :if={@cursor}
        type="button"
        class="btn btn-sm btn-outline"
        phx-click={@on_load_more}
        phx-value-cursor={@cursor}
        aria-label={gettext("Load more applications")}
      >
        {gettext("Load more")}
        <.icon name="hero-chevron-down" class="size-4" />
      </button>
    </nav>
    """
  end
end
