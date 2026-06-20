defmodule DebtStalkerWeb.ApplicationsLive do
  @moduledoc """
  LiveView for listing credit applications with filters, cursor pagination,
  and real-time updates via PubSub.
  """
  use DebtStalkerWeb, :live_view

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:list")
    end

    socket =
      socket
      |> assign(:page_title, "Applications")
      |> assign(:filters, %{})
      |> assign(:cursor, nil)
      |> load_applications()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{}

    filters =
      if params["country"], do: Map.put(filters, :country, params["country"]), else: filters

    filters = if params["status"], do: Map.put(filters, :status, params["status"]), else: filters

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:cursor, params["cursor"])
      |> load_applications()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"country" => country, "status" => status}, socket) do
    filters = %{}
    filters = if country != "", do: Map.put(filters, :country, country), else: filters
    filters = if status != "", do: Map.put(filters, :status, status), else: filters

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:cursor, nil)
      |> load_applications()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    socket =
      socket
      |> assign(:cursor, socket.assigns.next_cursor)
      |> load_applications()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:application_created, _app}, socket) do
    socket = load_applications(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_changed, _details}, socket) do
    socket = load_applications(socket)
    {:noreply, socket}
  end

  defp load_applications(socket) do
    filters =
      socket.assigns.filters
      |> Map.put(:limit, 20)
      |> maybe_put_cursor(socket.assigns[:cursor])

    result = Applications.list_applications(filters)

    socket
    |> assign(:applications, result.entries)
    |> assign(:next_cursor, result.cursor)
  end

  defp maybe_put_cursor(filters, nil), do: filters
  defp maybe_put_cursor(filters, cursor), do: Map.put(filters, :cursor, cursor)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold mb-4">Credit Applications</h1>

      <form id="filter-form" phx-change="filter" class="flex gap-4 mb-6">
        <select name="country" class="rounded border px-3 py-2">
          <option value="">All Countries</option>
          <option value="ES" selected={@filters[:country] == "ES"}>Spain (ES)</option>
          <option value="MX" selected={@filters[:country] == "MX"}>Mexico (MX)</option>
        </select>

        <select name="status" class="rounded border px-3 py-2">
          <option value="">All Statuses</option>
          <%= for status <- CreditApplication.valid_statuses() do %>
            <option value={status} selected={@filters[:status] == status}>
              {status}
            </option>
          <% end %>
        </select>
      </form>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Country</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Name</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Document</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Amount</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Status</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Review</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Date</th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for app <- @applications do %>
              <tr id={"app-#{app.id}"}>
                <td class="px-4 py-2 whitespace-nowrap">{app.country}</td>
                <td class="px-4 py-2 whitespace-nowrap">{app.full_name}</td>
                <td class="px-4 py-2 whitespace-nowrap font-mono">
                  {CreditApplication.redact_document(app.identity_document)}
                </td>
                <td class="px-4 py-2 whitespace-nowrap">{Decimal.to_string(app.requested_amount)}</td>
                <td class="px-4 py-2 whitespace-nowrap">
                  <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(app.status)}"}>
                    {app.status}
                  </span>
                </td>
                <td class="px-4 py-2 whitespace-nowrap">
                  <%= if app.additional_review_required do %>
                    <span class="text-amber-600 font-medium">Yes</span>
                  <% else %>
                    <span class="text-gray-400">No</span>
                  <% end %>
                </td>
                <td class="px-4 py-2 whitespace-nowrap text-sm">
                  {Calendar.strftime(app.application_date, "%Y-%m-%d %H:%M")}
                </td>
                <td class="px-4 py-2 whitespace-nowrap">
                  <.link navigate={~p"/applications/#{app.id}"} class="text-blue-600 hover:underline">
                    View
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if @next_cursor do %>
        <div class="mt-4">
          <button
            phx-click="next_page"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
          >
            Next Page
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_color("submitted"), do: "bg-blue-100 text-blue-800"
  defp status_color("pending_risk"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("additional_review"), do: "bg-amber-100 text-amber-800"
  defp status_color("approved"), do: "bg-green-100 text-green-800"
  defp status_color("rejected"), do: "bg-red-100 text-red-800"
  defp status_color("provider_error"), do: "bg-gray-100 text-gray-800"
  defp status_color("cancelled"), do: "bg-gray-100 text-gray-600"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
