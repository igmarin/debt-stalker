defmodule DebtStalkerWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard with filtered KPIs, real-time charts, and recent applications.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}

  alias DebtStalker.Applications
  alias DebtStalker.Countries.Registry, as: CountryRegistry
  alias DebtStalkerWeb.Admin.FilterParams

  import DebtStalkerWeb.Components.AdminFilters
  import DebtStalkerWeb.Components.Charts
  import DebtStalkerWeb.Components.UI

  @doc "Mounts the admin dashboard."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:list")
    end

    socket =
      socket
      |> assign(:page_title, gettext("Admin Dashboard"))
      |> assign(:country_options, CountryRegistry.supported_countries())

    {:ok, socket}
  end

  @doc "Loads dashboard data from URL filter parameters."
  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    filters = FilterParams.from_params(params)
    analytics = Applications.dashboard_analytics(filters)
    recent = Applications.list_applications(Map.merge(filters, %{page: 1, per_page: 8}))

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:stats, analytics.stats)
      |> assign(:status_breakdown, analytics.status_breakdown)
      |> assign(:by_country, analytics.by_country)
      |> assign(:timeline, analytics.timeline)
      |> assign(:recent, recent.entries)

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(%{
        country: blank_to_nil(params["country"]),
        status: blank_to_nil(params["status"]),
        date_from: parse_date(params["date_from"]),
        date_to: parse_date(params["date_to"])
      })
      |> drop_nil_values()

    {:noreply, push_patch(socket, to: ~p"/admin?#{FilterParams.to_query(filters)}")}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:application_created, _app}, socket) do
    {:noreply, reload_dashboard(socket)}
  end

  def handle_info({:status_changed, _details}, socket) do
    {:noreply, reload_dashboard(socket)}
  end

  @doc "Renders the dashboard."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        {gettext("Dashboard")}
        <:subtitle>
          {gettext("Manager overview with live metrics and application trends.")}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/admin/applications"} class="btn btn-primary btn-sm">
            {gettext("View all applications")}
          </.link>
        </:actions>
      </.header>

      <.filter_bar filters={@filters} country_options={@country_options} clear_path={~p"/admin"} />
      <.active_filter_chips filters={@filters} />

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4 mt-6">
        <.stat_card
          title={gettext("Total applications")}
          value={@stats.total}
          icon="hero-document-text"
        />
        <.stat_card title={gettext("Pending risk")} value={@stats.pending_risk} icon="hero-clock" />
        <.stat_card
          title={gettext("Additional review")}
          value={@stats.additional_review}
          icon="hero-exclamation-triangle"
        />
        <.stat_card
          title={gettext("Provider errors")}
          value={@stats.provider_errors}
          icon="hero-server-stack"
        />
        <.stat_card
          title={gettext("Decided today")}
          value={@stats.decided_today}
          description={gettext("Approved or rejected today")}
          icon="hero-check-circle"
        />
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 mt-8">
        <div class="card bg-base-100 shadow-sm xl:col-span-2">
          <div class="card-body">
            <h2 class="card-title text-lg">{gettext("Applications over time")}</h2>
            <p class="text-sm text-base-content/60 mb-2">{gettext("Last 7 days")}</p>
            <.timeline_chart data={@timeline} />
          </div>
        </div>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title text-lg">{gettext("Status distribution")}</h2>
            <.status_pie_chart data={@status_breakdown} />
          </div>
        </div>

        <div class="card bg-base-100 shadow-sm xl:col-span-3">
          <div class="card-body">
            <h2 class="card-title text-lg">{gettext("Applications by country")}</h2>
            <.country_bar_chart data={@by_country} />
          </div>
        </div>
      </div>

      <div class="card bg-base-100 shadow-sm mt-8">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h2 class="card-title text-lg">{gettext("Recent applications")}</h2>
            <.link
              navigate={~p"/admin/applications?#{FilterParams.to_query(@filters)}"}
              class="btn btn-ghost btn-sm"
            >
              {gettext("Open filtered list")}
            </.link>
          </div>

          <%= if @recent == [] do %>
            <.empty_state
              title={gettext("No applications yet")}
              description={
                gettext("Applications will appear here once applicants start submitting them.")
              }
            />
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>{gettext("Country")}</th>
                    <th>{gettext("Name")}</th>
                    <th>{gettext("Amount")}</th>
                    <th>{gettext("Status")}</th>
                    <th class="w-0"></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for app <- @recent do %>
                    <tr id={"recent-app-#{app.id}"}>
                      <td>{app.country}</td>
                      <td>{app.full_name}</td>
                      <td>{Decimal.to_string(app.requested_amount)}</td>
                      <td><.status_badge status={app.status} /></td>
                      <td>
                        <.link
                          navigate={~p"/admin/applications/#{app.id}"}
                          class="btn btn-ghost btn-xs"
                        >
                          {gettext("View")}
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp reload_dashboard(socket) do
    analytics = Applications.dashboard_analytics(socket.assigns.filters)

    recent =
      Applications.list_applications(Map.merge(socket.assigns.filters, %{page: 1, per_page: 8}))

    socket
    |> assign(:stats, analytics.stats)
    |> assign(:status_breakdown, analytics.status_breakdown)
    |> assign(:by_country, analytics.by_country)
    |> assign(:timeline, analytics.timeline)
    |> assign(:recent, recent.entries)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
