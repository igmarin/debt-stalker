defmodule DebtStalkerWeb.Components.Charts do
  @moduledoc """
  Server-rendered SVG charts for the admin dashboard using Contex.
  """

  use Phoenix.Component
  use Gettext, backend: DebtStalkerWeb.Gettext

  alias Contex.{BarChart, Dataset, Plot, SimplePie}

  import DebtStalkerWeb.Components.UI, only: [format_status: 1]

  @doc "Renders a status distribution pie chart."
  attr :data, :list, required: true
  attr :class, :any, default: nil

  @spec status_pie_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def status_pie_chart(assigns) do
    assigns = assign(assigns, :svg, build_status_pie(assigns.data))

    ~H"""
    <div class={@class}>
      <%= if @svg do %>
        <div class="w-full flex justify-center overflow-x-auto">{Phoenix.HTML.raw(@svg)}</div>
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
    assigns = assign(assigns, :svg, build_timeline_chart(assigns.data))

    ~H"""
    <div class={@class}>
      <%= if @svg do %>
        <div class="w-full overflow-x-auto">{Phoenix.HTML.raw(@svg)}</div>
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
    assigns = assign(assigns, :svg, build_country_chart(assigns.data))

    ~H"""
    <div class={@class}>
      <%= if @svg do %>
        <div class="w-full overflow-x-auto">{Phoenix.HTML.raw(@svg)}</div>
      <% else %>
        <p class="text-sm text-base-content/60 text-center py-8">{gettext("No data for chart")}</p>
      <% end %>
    </div>
    """
  end

  defp build_status_pie([]), do: nil

  defp build_status_pie(data) do
    tuples =
      Enum.map(data, fn %{status: status, count: count} ->
        {format_status(status), count}
      end)

    %SimplePie{SimplePie.new(tuples) | height: 240}
    |> SimplePie.draw()
    |> safe_content()
  end

  defp build_timeline_chart([]), do: nil

  defp build_timeline_chart(data) do
    if Enum.all?(data, &(&1.count == 0)) do
      nil
    else
      rows =
        Enum.map(data, fn %{date: date, count: count} ->
          {Calendar.strftime(date, "%m-%d"), count}
        end)

      rows
      |> Dataset.new(["day", "count"])
      |> then(&Plot.new(&1, BarChart, 520, 220))
      |> Plot.to_svg()
      |> safe_content()
    end
  end

  defp build_country_chart([]), do: nil

  defp build_country_chart(data) do
    rows = Enum.map(data, fn %{country: country, count: count} -> {country, count} end)

    rows
    |> Dataset.new(["country", "count"])
    |> then(&Plot.new(&1, BarChart, 480, 220))
    |> Plot.to_svg()
    |> safe_content()
  end

  defp safe_content({:safe, content}), do: content
  defp safe_content(_), do: nil
end
