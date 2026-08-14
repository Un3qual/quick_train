defmodule QuickTrain.Audit do
  @moduledoc "Append-only audit recording."

  alias QuickTrain.Audit.Record

  def record(attrs) do
    Record
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end
end
