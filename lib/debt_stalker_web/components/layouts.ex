defmodule DebtStalkerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DebtStalkerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the main application navbar.

  The navbar is persona-aware: applicants and admins see different links,
  and the landing page shows a minimal version.
  """
  attr :current_role, :string, default: nil

  @spec navbar(map()) :: Phoenix.LiveView.Rendered.t()
  def navbar(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1 min-w-0">
        <.link navigate={home_path(@current_role)} class="flex items-center gap-2 text-lg font-bold">
          <.icon name="hero-shield-check" class="size-6 text-primary shrink-0" />
          <span class="truncate">Debt Stalker</span>
        </.link>
      </div>

      <div class="flex-none flex items-center gap-2">
        <nav :if={@current_role == "admin"} class="hidden md:block">
          <ul class="flex items-center gap-1">
            <li>
              <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">Dashboard</.link>
            </li>
            <li>
              <.link navigate={~p"/admin/applications"} class="btn btn-ghost btn-sm">
                Applications
              </.link>
            </li>
            <li>
              <.form
                for={%{}}
                id="switch-to-applicant"
                action={~p"/set-role"}
                method="post"
                class="inline"
              >
                <input type="hidden" name="role" value="applicant" />
                <button type="submit" class="btn btn-ghost btn-sm">Switch to applicant</button>
              </.form>
            </li>
            <li>
              <.link href={~p"/admin/logout"} method="delete" class="btn btn-ghost btn-sm">
                Log out
              </.link>
            </li>
          </ul>
        </nav>

        <div :if={@current_role == "admin"} class="dropdown dropdown-end md:hidden">
          <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-square" aria-label="Menu">
            <.icon name="hero-bars-3" class="size-5" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-box z-50 mt-3 w-52 p-2 shadow border border-base-200"
          >
            <li><.link navigate={~p"/admin"} class="justify-start">Dashboard</.link></li>
            <li>
              <.link navigate={~p"/admin/applications"} class="justify-start">Applications</.link>
            </li>
            <li>
              <.form for={%{}} id="switch-to-applicant-mobile" action={~p"/set-role"} method="post">
                <input type="hidden" name="role" value="applicant" />
                <button type="submit" class="w-full text-left px-4 py-2">Switch to applicant</button>
              </.form>
            </li>
            <li>
              <.link href={~p"/admin/logout"} method="delete" class="justify-start">Log out</.link>
            </li>
          </ul>
        </div>

        <nav :if={@current_role == "applicant"} class="hidden sm:block">
          <.link href={~p"/admin/logout"} method="delete" class="btn btn-ghost btn-sm">
            Log out
          </.link>
        </nav>

        <div :if={@current_role == "applicant"} class="dropdown dropdown-end sm:hidden">
          <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-square" aria-label="Menu">
            <.icon name="hero-bars-3" class="size-5" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-box z-50 mt-3 w-40 p-2 shadow border border-base-200"
          >
            <li>
              <.link href={~p"/admin/logout"} method="delete" class="justify-start">Log out</.link>
            </li>
          </ul>
        </div>

        <.theme_toggle />
      </div>
    </header>
    """
  end

  defp home_path("admin"), do: ~p"/admin"
  defp home_path("applicant"), do: ~p"/apply"
  defp home_path(_), do: ~p"/"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  @spec theme_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
