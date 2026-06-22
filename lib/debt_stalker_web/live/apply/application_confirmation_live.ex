defmodule DebtStalkerWeb.Apply.ApplicationConfirmationLive do
  @moduledoc """
  Applicant-facing confirmation and status tracker.

  Shows a summary of the submitted application and subscribes to real-time
  status updates for the referenced application.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :applicant}

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication

  import DebtStalkerWeb.Components.UI

  @doc "Mounts the confirmation/tracker page."
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
          |> assign(:page_title, "Application Submitted")
          |> assign(:app, app)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Application not found")
         |> redirect(to: ~p"/apply")}
    end
  end

  @doc "Refreshes the application when its status changes."
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:status_changed, _details}, socket) do
    case Applications.get_application(socket.assigns.app.id) do
      {:ok, app} ->
        {:noreply,
         socket
         |> assign(:app, app)
         |> put_flash(:info, "Status updated to #{format_status(app.status)}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Application no longer available")}
    end
  end

  @doc "Renders the confirmation page."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.link navigate={~p"/apply"} class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> New application
      </.link>

      <div class="card bg-base-100 shadow-sm">
        <div class="card-body text-center">
          <div class="mx-auto bg-success/10 text-success rounded-full p-4 w-fit mb-4">
            <.icon name="hero-check-circle" class="size-10" />
          </div>

          <h1 class="card-title text-2xl justify-center">Application received</h1>
          <p class="text-base-content/70 mb-2">
            Your reference ID is <span class="font-mono font-bold">{@app.id}</span>. Save it to track your application later.
          </p>

          <button
            type="button"
            class="btn btn-ghost btn-sm mb-6"
            phx-click={JS.dispatch("phx:copy", detail: %{text: @app.id})}
          >
            <.icon name="hero-clipboard-document" class="size-4" /> Copy reference ID
          </button>

          <div class="flex justify-center mb-6" aria-live="polite" aria-atomic="true">
            <.status_badge status={@app.status} class="badge-lg" />
          </div>

          <div :if={@app.additional_review_required} class="alert alert-warning mb-6">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>Your application has been flagged for additional review.</span>
          </div>
        </div>
      </div>

      <div class="card bg-base-100 shadow-sm mt-6">
        <div class="card-body">
          <h2 class="card-title text-lg mb-4">Application summary</h2>
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
              <dt class="text-base-content/60">Submitted at</dt>
              <dd class="font-medium">
                {Calendar.strftime(@app.application_date, "%Y-%m-%d %H:%M:%S UTC")}
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    """
  end
end
