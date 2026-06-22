defmodule DebtStalkerWeb.Components.UI do
  @moduledoc """
  Shared application UI components for the Debt Stalker interface.

  These components are intentionally thin: they rely on DaisyUI + Tailwind
  classes and the existing `DebtStalkerWeb.CoreComponents.icon/1` helper.
  """

  use Phoenix.Component

  import DebtStalkerWeb.CoreComponents, only: [icon: 1]

  alias DebtStalker.Applications.CreditApplication

  @doc """
  Renders a status badge for a credit application.
  """
  attr :status, :string, required: true
  attr :class, :any, default: nil

  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def status_badge(assigns) do
    assigns =
      assign_new(assigns, :badge_class, fn -> status_badge_class(assigns.status) end)

    ~H"""
    <span class={["badge", @badge_class, @class]}>
      {format_status(@status)}
    </span>
    """
  end

  @doc """
  Renders a dashboard statistic card.
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, default: nil
  attr :description, :string, default: nil
  attr :class, :any, default: nil

  @spec stat_card(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_card(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-sm", @class]}>
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div>
            <p class="text-sm text-base-content/70">{@title}</p>
            <p class="text-2xl font-bold mt-1">{@value}</p>
          </div>
          <div :if={@icon} class="bg-base-200 rounded-lg p-2">
            <.icon name={@icon} class="size-5 text-base-content/70" />
          </div>
        </div>
        <p :if={@description} class="text-xs text-base-content/60 mt-2">
          {@description}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state illustration/message.
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :description, :string, default: nil

  slot :action

  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="bg-base-200 rounded-full p-4 mb-4">
        <.icon name={@icon} class="size-8 text-base-content/50" />
      </div>
      <h3 class="text-lg font-semibold">{@title}</h3>
      <p :if={@description} class="text-sm text-base-content/70 mt-1 max-w-sm">
        {@description}
      </p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an audit trail timeline for an application.
  """
  attr :entries, :list, required: true

  @spec audit_timeline(map()) :: Phoenix.LiveView.Rendered.t()
  def audit_timeline(assigns) do
    ~H"""
    <ul class="timeline timeline-vertical timeline-compact">
      <li :for={entry <- @entries} class="timeline-item">
        <hr class="bg-base-300" />
        <div class="timeline-start text-xs text-base-content/60">
          {format_datetime(entry.inserted_at)}
        </div>
        <div class="timeline-middle">
          <.icon name="hero-check-circle" class="size-4 text-base-content/40" />
        </div>
        <div class="timeline-end timeline-box bg-base-100 shadow-sm text-sm">
          <p class="font-medium">{format_audit_action(entry.action)}</p>
          <p class="text-xs text-base-content/70">
            Actor: {entry.actor}
            <span :if={entry.metadata["from"] && entry.metadata["to"]}>
              {format_status(entry.metadata["from"])} → {format_status(entry.metadata["to"])}
            </span>
          </p>
        </div>
        <hr class="bg-base-300" />
      </li>
    </ul>
    """
  end

  defp status_badge_class(status) do
    case status do
      "submitted" -> "badge-info"
      "pending_risk" -> "badge-warning"
      "additional_review" -> "badge-secondary"
      "approved" -> "badge-success"
      "rejected" -> "badge-error"
      "provider_error" -> "badge-neutral"
      "cancelled" -> "badge-ghost"
      _ -> "badge-ghost"
    end
  end

  @doc "Formats a status atom or string for display."
  @spec format_status(atom() | String.t() | nil) :: String.t()
  def format_status(nil), do: ""

  def format_status(status) when is_atom(status) do
    status |> Atom.to_string() |> format_status()
  end

  def format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_audit_action("status_changed"), do: "Status changed"
  defp format_audit_action(action), do: format_status(action)

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: ""

  @doc """
  Returns the list of valid application statuses for use in select inputs.
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(CreditApplication.valid_statuses(), fn status ->
      {format_status(status), status}
    end)
  end
end
