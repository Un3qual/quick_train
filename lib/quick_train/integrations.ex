defmodule QuickTrain.Integrations do
  @moduledoc "Provider-neutral credentials, external references, and webhook receipts."

  alias QuickTrain.Integrations.WebhookReceipt

  def record_webhook(attrs) do
    WebhookReceipt
    |> Ash.Changeset.for_create(:record, attrs)
    |> Ash.create(authorize?: false)
  end
end
