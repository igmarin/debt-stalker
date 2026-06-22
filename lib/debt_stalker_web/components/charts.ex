defmodule DebtStalkerWeb.Components.Charts do
  @moduledoc """
  Client-rendered charts for the admin dashboard using Chart.js.

  Each chart renders a `<canvas>` with data attributes; the `ChartHook` in
  `app.js` mounts the Chart.js instance. This gives us tooltips, legends, and
  accessibility labels while keeping the server payload small.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  import DebtStalkerWeb.Components.UI, only: [format_status: 1]

  @status_colors %{
    "submitted" => "rgba(59, 130, 246, 0.8)",
    "pending_risk" => "rgba(245, 158, 11, 0.8)",
    "additional_review" => "rgba(139, 92, 246, 0.8)",
    "approved" => "rgba(34, 197, 94, 0.8)",
    "rejected" => "rgba(239, 68, 68, 0.8)",
    "provider_error" => "rgba(107, 114, 128, 0.8)",
    "cancelled" => "rgba(156, 163, 175, 0.8)"
  }

  @doc "Renders a status distribution pie chart."
  attr :data, :list, required: true
  attr :class, :any, default: nil

  @spec status_pie_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def status_pie_chart(assigns) do
    assigns =
      assign(assigns, :chart_data, build_status_pie_data(assigns.data))

    ~H"""
    <div class={[@class, "h-64"]}>
      <%= if @chart_data do %>
        <canvas
          id={"status-pie-#{System.unique_integer([:positive])}"}
          phx-hook="ChartHook"
          data-chart-type="pie"
          data-chart-datasets={Jason.encode!(@chart_data)}
          aria-label={gettext("Status distribution chart")}
        >
        </canvas>
      <% else %>
        <p class="text-sm text-base-content/60 text-center py-8">{gettext("No data for chart")}</p>
      <% end %>
    </div>
    """
  end

  @doc "Renders a daily applications timeline chart."
  attr :data, :list, required: true
  attr :class, :any, default: nil

  @spec timeline_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def timeline_chart(assigns) do
    assigns =
      assign(assigns, :chart_data, build_timeline_data(assigns.data))

    ~H"""
    <div class={[@class, "h-64"]}>
      <%= if @chart_data do %>
        <canvas
          id={"timeline-#{System.unique_integer([:positive])}"}
          phx-hook="ChartHook"
          data-chart-type="bar"
          data-chart-datasets={Jason.encode!(@chart_data)}
          aria-label={gettext("Applications over time chart")}
        >
        </canvas>
      <% else %>
        <p class="text-sm text-base-content/60 text-center py-8">{gettext("No data for chart")}</p>
      <% end %>
    </div>
    """
  end

  @doc "Renders a country breakdown bar chart."
  attr :data, :list, required: true
  attr :class, :any, default: nil

  @spec country_bar_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def country_bar_chart(assigns) do
    assigns =
      assign(assigns, :chart_data, build_country_data(assigns.data))

    ~H"""
    <div class={[@class, "h-64"]}>
      <%= if @chart_data do %>
        <canvas
          id={"country-bar-#{System.unique_integer([:positive])}"}
          phx-hook="ChartHook"
          data-chart-type="bar"
          data-chart-datasets={Jason.encode!(@chart_data)}
          aria-label={gettext("Applications by country chart")}
        >
        </canvas>
      <% else %>
        <p class="text-sm text-base-content/60 text-center py-8">{gettext("No data for chart")}</p>
      <% end %>
    </div>
    """
  end

  defp build_status_pie_data([]), do: nil

  defp build_status_pie_data(data) do
    labels = Enum.map(data, &format_status(&1.status))
    values = Enum.map(data, & &1.count)
    background_color = Enum.map(data, &Map.get(@status_colors, &1.status, "rgba(59, 130, 246, 0.8)"))

    %{
      type: "pie",
      data: %{
        labels: labels,
        datasets: [
          %{
            data: values,
            backgroundColor: background_color,
            borderWidth: 0
          }
        ]
      }
    }
  end

  defp build_timeline_data([]), do: nil

  defp build_timeline_data(data) do
    if Enum.all?(data, &(&1.count == 0)) do
      nil
    else
      labels = Enum.map(data, &Calendar.strftime(&1.date, "%m-%d"))
      values = Enum.map(data, & &1.count)

      %{
        type: "bar",
        data: %{
          labels: labels,
          datasets: [
            %{
              label: gettext("Applications"),
              data: values,
              backgroundColor: "rgba(59, 130, 246, 0.7)",
              borderRadius: 4
            }
          ]
        }
      }
    end
  end

  defp build_country_data([]), do: nil

  defp build_country_data(data) do
    labels = Enum.map(data, & &1.country)
    values = Enum.map(data, & &1.count)

    %{
      type: "bar",
      data: %{
        labels: labels,
        datasets: [
          %{
            label: gettext("Applications"),
            data: values,
            backgroundColor: "rgba(16, 185, 129, 0.7)",
            borderRadius: 4
          }
        ]
      }
    }
  end
end
