defmodule DebtStalkerWeb.Admin.ApplicationsLive do
  @moduledoc """
  Admin-facing list of credit applications with filters, sorting, and bounded
  page-based pagination.

  Subscribes to the applications PubSub topic so the list updates in real time.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries.Registry, as: CountryRegistry
  alias DebtStalkerWeb.Admin.FilterParams

  import DebtStalkerWeb.Components.AdminFilters
  import DebtStalkerWeb.Components.Pagination
  import DebtStalkerWeb.Components.UI

  @default_per_page 20

  @doc "Mounts the admin applications list."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:list")
    end

    socket =
      socket
      |> assign(:page_title, gettext("Applications"))
      |> assign(:country_options, CountryRegistry.supported_countries())
      |> assign(:highlighted_id, nil)

    {:ok, socket}
  end

  @doc "Applies filters, sort, and page pagination from URL parameters."
  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    filters =
      params
      |> FilterParams.from_params()
      |> Map.put_new(:page, 1)
      |> Map.put_new(:per_page, @default_per_page)

    result = Applications.list_applications(filters)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:applications, result.entries)
      |> assign(:page, result.page)
      |> assign(:per_page, result.per_page)
      |> assign(:total_count, result.total_count)
      |> assign(:total_pages, result.total_pages)

    {:noreply, socket}
  end

  @doc "Handles list interactions (filters, load more, and sorting)."
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
      |> Map.delete(:cursor)
      |> Map.delete(:page)
      |> drop_nil_values()
      |> Map.put_new(:page, 1)
      |> Map.put_new(:per_page, @default_per_page)

    {:noreply, push_patch(socket, to: ~p"/admin/applications?#{FilterParams.to_query(filters)}")}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    filters =
      socket.assigns.filters
      |> Map.put(:page, page)
      |> Map.put_new(:per_page, @default_per_page)

    {:noreply, push_patch(socket, to: ~p"/admin/applications?#{FilterParams.to_query(filters)}")}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    filters = FilterParams.toggle_sort(socket.assigns.filters, field)
    {:noreply, push_patch(socket, to: ~p"/admin/applications?#{FilterParams.to_query(filters)}")}
  end

  @doc "Refreshes the list when applications are created or updated."
  @impl true
  def handle_info({:application_created, app}, socket) do
    {:noreply, refresh_with_highlight(socket, app.id)}
  end

  def handle_info({:status_changed, %{application_id: id}}, socket) do
    {:noreply, refresh_with_highlight(socket, id)}
  end

  def handle_info({:status_changed, _details}, socket) do
    {:noreply, reload_list(socket)}
  end

  def handle_info({:clear_highlight, _id}, socket) do
    {:noreply, assign(socket, :highlighted_id, nil)}
  end

  @doc "Renders the applications list."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.header>
        {gettext("Applications")}
        <:subtitle>{gettext("Review and manage credit applications.")}</:subtitle>
      </.header>

      <.filter_bar
        filters={@filters}
        country_options={@country_options}
        clear_path={~p"/admin/applications"}
      />
      <.active_filter_chips filters={@filters} />

      <div class="card bg-base-100 shadow-sm mt-6">
        <div class="card-body p-0 sm:p-6">
          <%= if @applications == [] do %>
            <div class="p-6">
              <.empty_state
                title={gettext("No applications found")}
                description={
                  gettext("Try adjusting the filters or wait for new applications to arrive.")
                }
              />
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full">
                <thead>
                  <tr>
                    <.sortable_header field="country" label={gettext("Country")} filters={@filters} />
                    <.sortable_header field="full_name" label={gettext("Name")} filters={@filters} />
                    <th>{gettext("Document")}</th>
                    <.sortable_header
                      field="requested_amount"
                      label={gettext("Amount")}
                      filters={@filters}
                    />
                    <.sortable_header field="status" label={gettext("Status")} filters={@filters} />
                    <th>{gettext("Review")}</th>
                    <.sortable_header
                      field="application_date"
                      label={gettext("Date")}
                      filters={@filters}
                    />
                    <th class="w-0"></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for app <- @applications do %>
                    <tr id={"app-#{app.id}"} class={row_highlight_class(app.id, @highlighted_id)}>
                      <td>{app.country}</td>
                      <td class="whitespace-nowrap">
                        {app.full_name}
                      </td>
                      <td class="font-mono">
                        {CreditApplication.redact_document(app.identity_document)}
                      </td>
                      <td>{format_money(app.requested_amount, app.country)}</td>
                      <td><.status_badge status={app.status} /></td>
                      <td>
                        <%= if app.additional_review_required do %>
                          <span class="text-warning font-medium">{gettext("Yes")}</span>
                        <% else %>
                          <span class="text-base-content/40">{gettext("No")}</span>
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
                          {gettext("View")}
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <div class="p-6 border-t border-base-200">
              <.pagination
                page={@page}
                per_page={@per_page}
                total_count={@total_count}
                total_pages={@total_pages}
              />
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :filters, :map, required: true

  defp sortable_header(assigns) do
    active? = Map.get(assigns.filters, :sort_by, "application_date") == assigns.field
    direction = Map.get(assigns.filters, :sort_dir, "desc")

    assigns =
      assigns
      |> assign(:active?, active?)
      |> assign(:direction, direction)

    ~H"""
    <th>
      <button
        type="button"
        class={["flex items-center gap-1 font-semibold", @active? && "text-primary"]}
        phx-click="sort"
        phx-value-field={@field}
      >
        {@label}
        <.icon :if={@active? and @direction == "asc"} name="hero-chevron-up" class="size-3" />
        <.icon :if={@active? and @direction == "desc"} name="hero-chevron-down" class="size-3" />
      </button>
    </th>
    """
  end

  defp reload_list(socket) do
    filters =
      socket.assigns.filters
      |> Map.put_new(:page, 1)
      |> Map.put_new(:per_page, @default_per_page)

    result = Applications.list_applications(filters)

    socket
    |> assign(:applications, result.entries)
    |> assign(:page, result.page)
    |> assign(:per_page, result.per_page)
    |> assign(:total_count, result.total_count)
    |> assign(:total_pages, result.total_pages)
  end

  defp refresh_with_highlight(socket, id) do
    if connected?(socket) do
      Process.send_after(self(), {:clear_highlight, id}, 2_000)
    end

    socket
    |> reload_list()
    |> assign(:highlighted_id, id)
  end

  defp row_highlight_class(id, id), do: "bg-primary/15 transition-colors duration-1000"
  defp row_highlight_class(_id, _highlighted_id), do: nil

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
