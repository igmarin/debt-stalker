defmodule DebtStalkerWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard with KPI cards and a recent applications table.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}

  alias DebtStalker.Applications

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
      |> assign(:page_title, "Admin Dashboard")
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:application_created, _app}, socket) do
    {:noreply, load_dashboard(socket)}
  end

  def handle_info({:status_changed, _details}, socket) do
    {:noreply, load_dashboard(socket)}
  end

  @doc "Renders the dashboard."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        Dashboard
        <:subtitle>Overview of credit applications across all countries.</:subtitle>
      </.header>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4 mt-6">
        <.stat_card title="Total applications" value={@stats.total} icon="hero-document-text" />
        <.stat_card title="Pending risk" value={@stats.pending_risk} icon="hero-clock" />
        <.stat_card
          title="Additional review"
          value={@stats.additional_review}
          icon="hero-exclamation-triangle"
        />
        <.stat_card
          title="Provider errors"
          value={@stats.provider_errors}
          icon="hero-server-stack"
        />
        <.stat_card
          title="Decided today"
          value={@stats.decided_today}
          description="Approved or rejected today"
          icon="hero-check-circle"
        />
      </div>

      <div class="card bg-base-100 shadow-sm mt-8">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h2 class="card-title text-lg">Recent applications</h2>
            <.link navigate={~p"/admin/applications"} class="btn btn-primary btn-sm">
              View all
            </.link>
          </div>

          <%= if @recent == [] do %>
            <.empty_state
              title="No applications yet"
              description="Applications will appear here once applicants start submitting them."
            />
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Country</th>
                    <th>Name</th>
                    <th>Amount</th>
                    <th>Status</th>
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
                          View
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

  defp load_dashboard(socket) do
    stats = %{
      total: Applications.count_applications(%{}),
      pending_risk: Applications.count_applications(%{status: "pending_risk"}),
      additional_review: Applications.count_applications(%{status: "additional_review"}),
      provider_errors: Applications.count_applications(%{status: "provider_error"}),
      decided_today: Applications.count_decided_today()
    }

    recent = Applications.list_applications(%{limit: 10}).entries

    socket
    |> assign(:stats, stats)
    |> assign(:recent, recent)
  end
end
