defmodule DebtStalkerWeb.Admin.ApplicationDetailLive do
  @moduledoc """
  Admin-facing detail page for a single credit application.

  Includes the application summary, provider data, audit trail, and a gated
  status transition control.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Audit

  import DebtStalkerWeb.Components.UI

  @doc "Mounts the admin detail page."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), list()}
  def mount(%{"id" => id}, _session, socket) do
    case Applications.get_application(id) do
      {:ok, app} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:#{app.id}")
        end

        socket =
          socket
          |> assign(:page_title, "Application #{app.id}")
          |> load_application(app)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Application not found")
         |> redirect(to: ~p"/admin/applications")}
    end
  end

  @doc "Handles manual status transitions."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("update_status", %{"status" => new_status}, socket) do
    case Applications.update_status(socket.assigns.app.id, new_status, "admin") do
      {:ok, app} ->
        {:noreply,
         socket
         |> load_application(app)
         |> put_flash(:info, "Status updated to #{format_status(app.status)}")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Invalid status transition")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Application not found")}
    end
  end

  @doc "Refreshes the page when the application status changes."
  @impl true
  def handle_info({:status_changed, _details}, socket) do
    case Applications.get_application(socket.assigns.app.id) do
      {:ok, app} ->
        {:noreply, load_application(socket, app)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Application no longer available")
         |> redirect(to: ~p"/admin/applications")}
    end
  end

  @doc "Renders the detail page."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link navigate={~p"/admin/applications"} class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> Back to list
      </.link>

      <.header>
        Application {@app.id}
        <:subtitle>
          Submitted {Calendar.strftime(@app.application_date, "%Y-%m-%d %H:%M:%S UTC")}
        </:subtitle>
        <:actions>
          <.status_badge status={@app.status} class="badge-lg" />
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        <div class="lg:col-span-2 space-y-6">
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Application details</h2>
              <dl class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div>
                  <dt class="text-base-content/60">Country</dt>
                  <dd class="font-medium">{@app.country}</dd>
                </div>
                <div>
                  <dt class="text-base-content/60">Full name</dt>
                  <dd class="font-medium">{@app.full_name}</dd>
                </div>
                <div>
                  <dt class="text-base-content/60">Identity document</dt>
                  <dd class="font-medium font-mono">
                    {CreditApplication.redact_document(@app.identity_document)}
                  </dd>
                </div>
                <div>
                  <dt class="text-base-content/60">Requested amount</dt>
                  <dd class="font-medium">{Decimal.to_string(@app.requested_amount)}</dd>
                </div>
                <div>
                  <dt class="text-base-content/60">Monthly income</dt>
                  <dd class="font-medium">{Decimal.to_string(@app.monthly_income)}</dd>
                </div>
                <div>
                  <dt class="text-base-content/60">Additional review</dt>
                  <dd class="font-medium">
                    <%= if @app.additional_review_required do %>
                      <span class="text-warning">Required</span>
                    <% else %>
                      <span class="text-base-content/40">No</span>
                    <% end %>
                  </dd>
                </div>
              </dl>
            </div>
          </div>

          <div :if={@app.provider_summary} class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-2">Provider summary</h2>
              <div class="collapse collapse-arrow bg-base-200">
                <input type="checkbox" />
                <div class="collapse-title text-sm font-medium">View normalized data</div>
                <div class="collapse-content">
                  <pre class="text-xs overflow-x-auto"><%= Jason.encode!(@app.provider_summary, pretty: true) %></pre>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-6">
          <div :if={@allowed_transitions != []} class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Update status</h2>
              <form id="status-update-form" phx-submit="update_status" class="space-y-4">
                <.input
                  type="select"
                  name="status"
                  label="New status"
                  value={List.first(@allowed_transitions)}
                  options={Enum.map(@allowed_transitions, &{format_status(&1), &1})}
                />
                <button type="submit" class="btn btn-primary w-full">
                  Update status
                </button>
              </form>
            </div>
          </div>

          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Audit trail</h2>
              <%= if @audit_logs == [] do %>
                <p class="text-sm text-base-content/60">No audit entries yet.</p>
              <% else %>
                <.audit_timeline entries={@audit_logs} />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_application(socket, app) do
    socket
    |> assign(:app, app)
    |> assign(:allowed_transitions, Applications.allowed_transitions(app))
    |> assign(:audit_logs, Audit.list_audit_logs(app.id))
  end
end
