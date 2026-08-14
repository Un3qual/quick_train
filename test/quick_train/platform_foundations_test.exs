defmodule QuickTrain.PlatformFoundationsTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Integrations, Operations}

  test "operation and webhook idempotency keys are stable" do
    request = %{source: "user", idempotency_key: "request-1", operation: "forms.create"}
    assert {:ok, first_operation} = Operations.start(request)
    assert {:ok, repeated_operation} = Operations.start(request)
    assert first_operation.id == repeated_operation.id

    receipt = %{provider: "workos", external_id: "evt_123", payload: %{"event" => "user.updated"}}
    assert {:ok, first_receipt} = Integrations.record_webhook(receipt)
    assert {:ok, repeated_receipt} = Integrations.record_webhook(receipt)
    assert first_receipt.id == repeated_receipt.id
  end
end
