defmodule DebtStalkerWeb.Components.UI do
  @moduledoc """
  Shared application UI components for the Debt Stalker interface.

  These components are intentionally thin: they rely on DaisyUI + Tailwind
  classes and the existing `DebtStalkerWeb.CoreComponents.icon/1` helper.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  import DebtStalkerWeb.CoreComponents, only: [icon: 1]

  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries

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
  Renders a loading skeleton placeholder.
  """
  attr :class, :any, default: nil

  @spec skeleton(map()) :: Phoenix.LiveView.Rendered.t()
  def skeleton(assigns) do
    ~H"""
    <div class={["skeleton rounded", @class]}></div>
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
          <.icon name={audit_icon(entry)} class={["size-4", audit_icon_class(entry)]} />
        </div>
        <div class="timeline-end timeline-box bg-base-100 shadow-sm text-sm">
          <p class="font-medium">{format_audit_action(entry.action)}</p>
          <p class="text-xs text-base-content/70">
            {gettext("Actor:")} {entry.actor}
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

  def format_status("submitted"), do: gettext("Submitted")
  def format_status("pending_risk"), do: gettext("Pending risk")
  def format_status("additional_review"), do: gettext("Additional review")
  def format_status("approved"), do: gettext("Approved")
  def format_status("rejected"), do: gettext("Rejected")
  def format_status("provider_error"), do: gettext("Provider error")
  def format_status("cancelled"), do: gettext("Cancelled")

  def format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_audit_action("status_changed"), do: gettext("Status changed")
  defp format_audit_action(action), do: format_status(action)

  defp audit_icon(%{action: "status_changed", metadata: %{"to" => status}}) do
    case status do
      "approved" -> "hero-check-circle"
      "rejected" -> "hero-x-circle"
      "additional_review" -> "hero-exclamation-triangle"
      "provider_error" -> "hero-server-stack"
      "cancelled" -> "hero-no-symbol"
      _ -> "hero-arrow-path"
    end
  end

  defp audit_icon(_entry), do: "hero-check-circle"

  defp audit_icon_class(%{action: "status_changed", metadata: %{"to" => status}}) do
    case status do
      "approved" -> "text-success"
      "rejected" -> "text-error"
      "additional_review" -> "text-warning"
      "provider_error" -> "text-neutral"
      "cancelled" -> "text-base-content/50"
      _ -> "text-base-content/40"
    end
  end

  defp audit_icon_class(_entry), do: "text-base-content/40"

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

  @doc """
  Formats a Decimal amount as money with a currency symbol and thousand separators.

  The currency symbol is resolved from the country code via the Countries context.
  Returns an empty string when `amount` is nil.

  ## Examples

      iex> format_money(Decimal.new("5000"), "MX")
      "$5,000"
      iex> format_money(Decimal.new("15000"), "ES")
      "€15,000"
  """
  @spec format_money(Decimal.t() | nil, String.t() | nil) :: String.t()
  def format_money(nil, _country), do: ""

  def format_money(%Decimal{} = amount, country) do
    symbol = Countries.currency_symbol(country)
    formatted = format_decimal_with_separators(amount)
    "#{symbol}#{formatted}"
  end

  @doc """
  Formats an integer with thousand separators for display of counts.

  ## Examples

      iex> format_number(4000)
      "4,000"
      iex> format_number(42)
      "42"
  """
  @spec format_number(integer() | nil) :: String.t()
  def format_number(nil), do: "0"

  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_decimal_with_separators(%Decimal{} = amount) do
    amount
    |> Decimal.to_string(:normal)
    |> String.split(".")
    |> case do
      [int_part] ->
        add_thousand_separators(int_part)

      [int_part, decimal_part] ->
        add_thousand_separators(int_part) <> "." <> decimal_part
    end
  end

  defp add_thousand_separators(number_string) do
    {sign, digits} =
      case number_string do
        "-" <> rest -> {"-", rest}
        _ -> {"", number_string}
      end

    formatted =
      digits
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()

    sign <> formatted
  end
end
