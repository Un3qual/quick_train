defmodule QuickTrain.DurableDelivery do
  @moduledoc "Durable domain-event persistence with an Oban-compatible dispatch seam."

  alias QuickTrain.DurableDelivery.DomainEvent

  def publish(attrs) do
    DomainEvent
    |> Ash.Changeset.for_create(:publish, attrs)
    |> Ash.create(authorize?: false)
  end
end
