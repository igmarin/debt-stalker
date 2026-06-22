defmodule DebtStalkerWeb.Admin.ApplicationsLive do
  @moduledoc """
  Admin-facing list of credit applications with filters and cursor pagination.

  Subscribes to the applications PubSub topic so the list updates in real time.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries.Registry, as: CountryRegistry

  import DebtStalkerWeb.Components.UI

  @doc "Mounts the admin applications list."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:list")
    end

    socket =
      socket
      |> assign(:page_title, "Applications")
      |> assign(:country_options, CountryRegistry.supported_countries())
      |> assign(:status_options, status_options())
      |> assign(:filters, %{limit: 20})

    {:ok, socket}
  end

  @doc "Applies filters and cursor from URL parameters."
  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    filters =
      %{limit: 20}
      |> maybe_put(:country, params["country"])
      |> maybe_put(:status, params["status"])
      |> maybe_put(:date_from, parse_date(params["date_from"]))
      |> maybe_put(:date_to, parse_date(params["date_to"]))
      |> maybe_put(:cursor, params["cursor"])

    result = Applications.list_applications(filters)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:applications, result.entries)
      |> assign(:next_cursor, result.cursor)

    {:noreply, socket}
  end

  @doc "Handles list interactions (filters and pagination)."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", params, socket) do
    filters =
      %{limit: 20}
      |> maybe_put(:country, params["country"])
      |> maybe_put(:status, params["status"])
      |> maybe_put(:date_from, parse_date(params["date_from"]))
      |> maybe_put(:date_to, parse_date(params["date_to"]))

    query_params =
      %{}
      |> maybe_put("country", params["country"])
      |> maybe_put("status", params["status"])
      |> maybe_put("date_from", params["date_from"])
      |> maybe_put("date_to", params["date_to"])

    socket =
      socket
      |> assign(:filters, filters)
      |> apply_filters()

    {:noreply, push_patch(socket, to: ~p"/admin/applications?#{query_params}")}
  end

  def handle_event("next_page", _params, socket) do
    next_cursor = socket.assigns.next_cursor

    if next_cursor do
      {:noreply, push_patch(socket, to: ~p"/admin/applications?cursor=#{next_cursor}")}
    else
      {:noreply, socket}
    end
  end

  @doc "Refreshes the list when applications are created or updated."
  @impl true
  def handle_info({:application_created, _app}, socket) do
    {:noreply, apply_filters(socket)}
  end

  def handle_info({:status_changed, _details}, socket) do
    {:noreply, apply_filters(socket)}
  end

  @doc "Renders the applications list."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        Applications
        <:subtitle>Review and manage credit applications.</:subtitle>
      </.header>

      <div class="card bg-base-100 shadow-sm mt-6">
        <div class="card-body">
          <form
            id="filter-form"
            phx-change="filter"
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4"
          >
            <.input
              type="select"
              name="country"
              label="Country"
              value={@filters[:country]}
              prompt="All countries"
              options={Enum.map(@country_options, &{&1, &1})}
            />
            <.input
              type="select"
              name="status"
              label="Status"
              value={@filters[:status]}
              prompt="All statuses"
              options={@status_options}
            />
            <.input type="date" name="date_from" label="From" value={@filters[:date_from]} />
            <.input type="date" name="date_to" label="To" value={@filters[:date_to]} />
            <div class="flex items-end">
              <.link navigate={~p"/admin/applications"} class="btn btn-ghost w-full">
                Clear
              </.link>
            </div>
          </form>
        </div>
      </div>

      <div class="card bg-base-100 shadow-sm mt-6">
        <div class="card-body p-0 sm:p-6">
          <%= if @applications == [] do %>
            <div class="p-6">
              <.empty_state
                title="No applications found"
                description="Try adjusting the filters or wait for new applications to arrive."
              />
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>Country</th>
                    <th>Name</th>
                    <th>Document</th>
                    <th>Amount</th>
                    <th>Status</th>
                    <th>Review</th>
                    <th>Date</th>
                    <th class="w-0"></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for app <- @applications do %>
                    <tr id={"app-#{app.id}"}>
                      <td>{app.country}</td>
                      <td class="whitespace-nowrap">{app.full_name}</td>
                      <td class="font-mono">
                        {CreditApplication.redact_document(app.identity_document)}
                      </td>
                      <td>{Decimal.to_string(app.requested_amount)}</td>
                      <td><.status_badge status={app.status} /></td>
                      <td>
                        <%= if app.additional_review_required do %>
                          <span class="text-warning font-medium">Yes</span>
                        <% else %>
                          <span class="text-base-content/40">No</span>
                        <% end %>
                      </td>
                      <td class="whitespace-nowrap text-sm">
                        {Calendar.strftime(app.application_date, "%Y-%m-%d %H:%M")}
                      </td>
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

            <%= if @next_cursor do %>
              <div class="p-6 border-t border-base-200">
                <button phx-click="next_page" class="btn btn-primary w-full sm:w-auto">
                  Load more
                </button>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp apply_filters(socket) do
    result = Applications.list_applications(socket.assigns.filters)

    socket
    |> assign(:applications, result.entries)
    |> assign(:next_cursor, result.cursor)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end
end
