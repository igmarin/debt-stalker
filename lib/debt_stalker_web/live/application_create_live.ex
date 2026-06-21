defmodule DebtStalkerWeb.ApplicationCreateLive do
  @moduledoc """
  LiveView for creating a new credit application.
  Validates input and shows inline errors before submission.
  """
  use DebtStalkerWeb, :live_view

  alias DebtStalker.Applications

  @doc "Mounts the new application form LiveView."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "New Application")
      |> assign(
        :form,
        to_form(
          %{
            "country" => "",
            "full_name" => "",
            "identity_document" => "",
            "requested_amount" => "",
            "monthly_income" => ""
          },
          as: "application"
        )
      )
      |> assign(:errors, %{})
      |> assign(:submitted, false)

    {:ok, socket}
  end

  @doc "Validates form input on change."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"application" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: "application"))}
  end

  def handle_event("save", %{"application" => params}, socket) do
    attrs = %{
      country: params["country"],
      full_name: params["full_name"],
      identity_document: params["identity_document"],
      requested_amount: safe_decimal(params["requested_amount"]),
      monthly_income: safe_decimal(params["monthly_income"])
    }

    case Applications.create_application(attrs) do
      {:ok, app} ->
        socket =
          socket
          |> put_flash(:info, "Application created successfully")
          |> redirect(to: "/applications/#{app.id}")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_errors(changeset)
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  defp safe_decimal(""), do: nil
  defp safe_decimal(nil), do: nil

  defp safe_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc "Renders the new application form UI."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6">
      <.link navigate={~p"/applications"} class="text-blue-600 hover:underline mb-4 inline-block">
        &larr; Back to list
      </.link>

      <h1 class="text-2xl font-bold mb-6">New Credit Application</h1>

      <form id="create-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700">Country</label>
          <select name="application[country]" class="mt-1 block w-full rounded border px-3 py-2">
            <option value="">Select country</option>
            <option value="ES" selected={@form.params["country"] == "ES"}>Spain (ES)</option>
            <option value="MX" selected={@form.params["country"] == "MX"}>Mexico (MX)</option>
          </select>
          <%= if @errors[:country] do %>
            <p class="text-red-600 text-sm mt-1">{Enum.join(@errors[:country], ", ")}</p>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700">Full Name</label>
          <input
            type="text"
            name="application[full_name]"
            value={@form.params["full_name"]}
            class="mt-1 block w-full rounded border px-3 py-2"
          />
          <%= if @errors[:full_name] do %>
            <p class="text-red-600 text-sm mt-1">{Enum.join(@errors[:full_name], ", ")}</p>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700">Identity Document</label>
          <input
            type="text"
            name="application[identity_document]"
            value={@form.params["identity_document"]}
            class="mt-1 block w-full rounded border px-3 py-2"
            placeholder={
              if @form.params["country"] == "ES",
                do: "12345678Z (DNI)",
                else: "GARC850101HDFRRL09 (CURP)"
            }
          />
          <%= if @errors[:identity_document] do %>
            <p class="text-red-600 text-sm mt-1">{Enum.join(@errors[:identity_document], ", ")}</p>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700">Requested Amount</label>
          <input
            type="number"
            step="0.01"
            name="application[requested_amount]"
            value={@form.params["requested_amount"]}
            class="mt-1 block w-full rounded border px-3 py-2"
          />
          <%= if @errors[:requested_amount] do %>
            <p class="text-red-600 text-sm mt-1">{Enum.join(@errors[:requested_amount], ", ")}</p>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700">Monthly Income</label>
          <input
            type="number"
            step="0.01"
            name="application[monthly_income]"
            value={@form.params["monthly_income"]}
            class="mt-1 block w-full rounded border px-3 py-2"
          />
          <%= if @errors[:monthly_income] do %>
            <p class="text-red-600 text-sm mt-1">{Enum.join(@errors[:monthly_income], ", ")}</p>
          <% end %>
        </div>

        <button
          type="submit"
          class="w-full bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700 font-medium"
        >
          Create Application
        </button>
      </form>
    </div>
    """
  end
end
