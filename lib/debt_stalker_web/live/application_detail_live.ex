defmodule DebtStalkerWeb.ApplicationDetailLive do
  @moduledoc """
  LiveView for displaying a single credit application detail with
  real-time status updates and manual status transition controls.
  """
  use DebtStalkerWeb, :live_view

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Applications.get_application(id) do
      {:ok, app} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:#{app.id}")
        end

        {:ok,
         socket
         |> assign(:app, app)
         |> assign(:allowed_transitions, Applications.allowed_transitions(app))
         |> assign(:page_title, "Application #{app.id}")}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "Application not found") |> redirect(to: "/applications")}
    end
  end

  @impl true
  def handle_event("update_status", %{"status" => new_status}, socket) do
    case Applications.update_status(socket.assigns.app.id, new_status, "ui") do
      {:ok, app} ->
        {:noreply,
         socket
         |> assign(:app, app)
         |> assign(:allowed_transitions, Applications.allowed_transitions(app))
         |> put_flash(:info, "Status updated to #{new_status}")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Invalid status transition")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Application not found")}
    end
  end

  @impl true
  def handle_info({:status_changed, _details}, socket) do
    {:ok, app} = Applications.get_application(socket.assigns.app.id)

    {:noreply,
     socket
     |> assign(:app, app)
     |> assign(:allowed_transitions, Applications.allowed_transitions(app))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-6">
      <.link navigate={~p"/applications"} class="text-blue-600 hover:underline mb-4 inline-block">
        &larr; Back to list
      </.link>

      <h1 class="text-2xl font-bold mb-6">Application Detail</h1>

      <div class="bg-white shadow rounded-lg p-6 space-y-4">
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="text-sm font-medium text-gray-500">ID</label>
            <p class="font-mono text-sm">{@app.id}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Country</label>
            <p>{@app.country}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Full Name</label>
            <p>{@app.full_name}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Document</label>
            <p class="font-mono">{CreditApplication.redact_document(@app.identity_document)}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Requested Amount</label>
            <p>{Decimal.to_string(@app.requested_amount)}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Monthly Income</label>
            <p>{Decimal.to_string(@app.monthly_income)}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Status</label>
            <p class="font-semibold">{@app.status}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Review Required</label>
            <p>{if @app.additional_review_required, do: "Yes", else: "No"}</p>
          </div>
          <div>
            <label class="text-sm font-medium text-gray-500">Application Date</label>
            <p>{Calendar.strftime(@app.application_date, "%Y-%m-%d %H:%M:%S")}</p>
          </div>
        </div>

        <%= if @app.provider_summary do %>
          <div class="mt-4">
            <label class="text-sm font-medium text-gray-500">Provider Summary</label>
            <pre class="mt-1 bg-gray-50 p-3 rounded text-xs"><%= Jason.encode!(@app.provider_summary, pretty: true) %></pre>
          </div>
        <% end %>
      </div>

      <%= if @allowed_transitions != [] do %>
        <div class="mt-6 bg-white shadow rounded-lg p-6">
          <h2 class="text-lg font-bold mb-4">Update Status</h2>
          <form id="status-update-form" phx-submit="update_status" class="flex gap-4 items-end">
            <div class="flex-1">
              <label class="block text-sm font-medium text-gray-700">New Status</label>
              <select name="status" class="mt-1 block w-full rounded border px-3 py-2">
                <%= for status <- @allowed_transitions do %>
                  <option value={status}>{status}</option>
                <% end %>
              </select>
            </div>
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 font-medium"
            >
              Update
            </button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end
end
