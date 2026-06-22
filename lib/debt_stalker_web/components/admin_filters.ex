defmodule DebtStalkerWeb.Components.AdminFilters do
  @moduledoc """
  Shared filter bar for admin LiveViews.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  import DebtStalkerWeb.CoreComponents, only: [input: 1, icon: 1]

  import DebtStalkerWeb.Components.UI, only: [status_options: 0]

  alias DebtStalkerWeb.Admin.FilterParams

  @doc "Renders the admin filter form bound to URL state."
  attr :filters, :map, required: true
  attr :country_options, :list, required: true
  attr :clear_path, :string, required: true
  attr :id, :string, default: "admin-filter-form"

  @spec filter_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_bar(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <form
          id={@id}
          phx-change="filter"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4"
        >
          <.input
            type="select"
            name="country"
            label={gettext("Country")}
            value={Map.get(@filters, :country)}
            prompt={gettext("All countries")}
            options={Enum.map(@country_options, &{&1, &1})}
          />
          <.input
            type="select"
            name="status"
            label={gettext("Status")}
            value={Map.get(@filters, :status)}
            prompt={gettext("All statuses")}
            options={status_options()}
          />
          <.input
            type="date"
            name="date_from"
            label={gettext("From")}
            value={FilterParams.format_date_for_input(Map.get(@filters, :date_from))}
          />
          <.input
            type="date"
            name="date_to"
            label={gettext("To")}
            value={FilterParams.format_date_for_input(Map.get(@filters, :date_to))}
          />
          <div class="flex items-end">
            <.link navigate={@clear_path} class="btn btn-ghost w-full gap-2">
              <.icon name="hero-x-mark" class="size-4" />
              {gettext("Clear")}
            </.link>
          </div>
        </form>
      </div>
    </div>
    """
  end

  @doc "Renders active filter chips for quick visual feedback."
  attr :filters, :map, required: true

  @spec active_filter_chips(map()) :: Phoenix.LiveView.Rendered.t()
  def active_filter_chips(assigns) do
    ~H"""
    <div :if={active_filters?(@filters)} class="flex flex-wrap gap-2 mt-4">
      <span :if={@filters[:country]} class="badge badge-outline gap-1">
        {gettext("Country")}: {@filters[:country]}
      </span>
      <span :if={@filters[:status]} class="badge badge-outline gap-1">
        {gettext("Status")}: {format_status_label(@filters[:status])}
      </span>
      <span :if={@filters[:date_from]} class="badge badge-outline gap-1">
        {gettext("From")}: {FilterParams.format_date_for_input(@filters[:date_from])}
      </span>
      <span :if={@filters[:date_to]} class="badge badge-outline gap-1">
        {gettext("To")}: {FilterParams.format_date_for_input(@filters[:date_to])}
      </span>
    </div>
    """
  end

  defp active_filters?(filters) do
    Enum.any?([:country, :status, :date_from, :date_to], &Map.get(filters, &1))
  end

  defp format_status_label(status) do
    DebtStalkerWeb.Components.UI.format_status(status)
  end
end
