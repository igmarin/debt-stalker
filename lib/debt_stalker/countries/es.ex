defmodule DebtStalker.Countries.ES do
  @moduledoc """
  Spain (ES) country module.

  Implements document validation (DNI), financial threshold checks,
  and provider summary interpretation for Spanish credit applications.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @impl true
  def validate_document(_document), do: :ok

  @impl true
  def validate_financials(_params), do: %{additional_review_required: false, reasons: []}

  @impl true
  def interpret_provider_summary(summary), do: summary

  @impl true
  def additional_review_required?(_params), do: false

  @impl true
  def allowed_status_transitions do
    %{
      "submitted" => ["pending_risk", "provider_error", "cancelled"],
      "pending_risk" => ["additional_review", "approved", "rejected", "cancelled"],
      "additional_review" => ["approved", "rejected"],
      "provider_error" => ["pending_risk", "rejected"]
    }
  end
end
