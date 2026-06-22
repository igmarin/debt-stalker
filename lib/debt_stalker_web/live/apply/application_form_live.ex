defmodule DebtStalkerWeb.Apply.ApplicationFormLive do
  @moduledoc """
  Applicant-facing LiveView for creating a new credit application.

  Validates input as the user types and redirects to a confirmation/tracker
  page on success.
  """

  use DebtStalkerWeb, :live_view

  on_mount {DebtStalkerWeb.Live.RoleAuth, :applicant}

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries
  alias DebtStalker.Countries.Registry, as: CountryRegistry

  @doc "Mounts the application form."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    form_params = Map.get(params, "application", %{})

    socket =
      socket
      |> assign(:page_title, gettext("Apply for Credit"))
      |> assign(:form, to_form(form_params, as: "application"))
      |> assign(:country_options, CountryRegistry.supported_countries())
      |> assign(:document_hint, Countries.get_document_hint(form_params["country"]))

    {:ok, socket}
  end

  @doc "Updates the document hint and form state on change."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"application" => params}, socket) do
    attrs = %{
      country: params["country"],
      full_name: params["full_name"],
      identity_document: params["identity_document"],
      requested_amount: safe_decimal(params["requested_amount"]),
      monthly_income: safe_decimal(params["monthly_income"]),
      birth_date: parse_optional_date(params["birth_date"])
    }

    changeset =
      %CreditApplication{}
      |> CreditApplication.changeset(attrs)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: "application"))
      |> assign(:document_hint, Countries.get_document_hint(params["country"]))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"application" => params}, socket) do
    attrs = %{
      country: params["country"],
      full_name: params["full_name"],
      identity_document: params["identity_document"],
      requested_amount: safe_decimal(params["requested_amount"]),
      monthly_income: safe_decimal(params["monthly_income"]),
      birth_date: parse_optional_date(params["birth_date"])
    }

    case Applications.create_application(attrs) do
      {:ok, app} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Application submitted successfully"))
         |> redirect(to: ~p"/apply/#{app.id}/confirmation")}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset, as: "application", action: :insert))
          |> assign(:document_hint, Countries.get_document_hint(params["country"]))

        {:noreply, socket}
    end
  end

  @doc "Renders the application form."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back")}
      </.link>

      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <h1 class="card-title text-2xl mb-2">{gettext("Apply for credit")}</h1>
          <p class="text-base-content/70 mb-6">
            {gettext(
              "Fill in your details. We will validate your document and income information for your country."
            )}
          </p>

          <ul class="steps steps-horizontal w-full mb-6 text-xs sm:text-sm">
            <li class={["step", step_active?(1, @form) && "step-primary"]}>{gettext("Country")}</li>
            <li class={["step", step_active?(2, @form) && "step-primary"]}>{gettext("Details")}</li>
            <li class="step">{gettext("Submit")}</li>
          </ul>

          <form id="apply-form" phx-change="validate" phx-submit="save" class="space-y-4">
            <.input
              field={@form[:country]}
              type="select"
              label={gettext("Country")}
              prompt={gettext("Select your country")}
              options={Enum.map(@country_options, &{&1, &1})}
            />

            <.input
              field={@form[:full_name]}
              type="text"
              label={gettext("Full name")}
              placeholder="Jane Doe"
            />

            <.input
              field={@form[:identity_document]}
              type="text"
              label={gettext("Identity document")}
              placeholder={@document_hint}
            />

            <.input
              field={@form[:birth_date]}
              type="date"
              label={gettext("Birth date (for document verification)")}
            />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@form[:requested_amount]}
                type="number"
                label={gettext("Requested amount")}
                step="0.01"
                placeholder="15000"
              />

              <.input
                field={@form[:monthly_income]}
                type="number"
                label={gettext("Monthly income")}
                step="0.01"
                placeholder="3000"
              />
            </div>

            <div class="pt-2">
              <button type="submit" class="btn btn-primary w-full">
                {gettext("Submit application")}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp safe_decimal(""), do: nil
  defp safe_decimal(nil), do: nil

  defp safe_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp step_active?(1, form), do: present?(form[:country].value)
  defp step_active?(2, form), do: step_active?(1, form) and present?(form[:full_name].value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp parse_optional_date(nil), do: nil
  defp parse_optional_date(""), do: nil

  defp parse_optional_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_optional_date(%Date{} = d), do: d
  defp parse_optional_date(_), do: nil
end
