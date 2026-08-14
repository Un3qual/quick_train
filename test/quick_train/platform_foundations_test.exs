defmodule QuickTrain.PlatformFoundationsTest do
  use QuickTrain.DataCase, async: true

  alias QuickTrain.{Audit, DurableDelivery, Integrations, Operations}

  test "operation, delivery, and webhook idempotency keys are stable" do
    request = %{source: "user", idempotency_key: "request-1", operation: "forms.create"}
    assert {:ok, first_operation} = Operations.start(request)
    assert {:ok, repeated_operation} = Operations.start(request)
    assert first_operation.id == repeated_operation.id

    event = %{topic: "form.created", idempotency_key: "event-1", payload: %{"id" => "form-1"}}
    assert {:ok, first_event} = DurableDelivery.publish(event)
    assert {:ok, repeated_event} = DurableDelivery.publish(event)
    assert first_event.id == repeated_event.id

    receipt = %{provider: "workos", external_id: "evt_123", payload: %{"event" => "user.updated"}}
    assert {:ok, first_receipt} = Integrations.record_webhook(receipt)
    assert {:ok, repeated_receipt} = Integrations.record_webhook(receipt)
    assert first_receipt.id == repeated_receipt.id
  end

  test "audit records retain generic provenance" do
    subject_id = Ecto.UUID.generate()

    assert {:ok, audit_record} =
             Audit.record(%{action: "form.updated", subject_type: "form", subject_id: subject_id})

    assert audit_record.subject_id == subject_id
  end
end
