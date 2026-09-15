defmodule QuickTrain.Tasks.Attempts.Receipt do
  @moduledoc "A terminal owner's receipt without response payloads or source access."
  use Ash.Resource,
    domain: QuickTrain.Tasks,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :id, :uuid, public?: true, primary_key?: true, allow_nil?: false
    attribute :state, :atom, public?: true, allow_nil?: false
    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :terminal_at, :utc_datetime_usec, public?: true
    attribute :inserted_at, :utc_datetime_usec, public?: true
    attribute :accepted, :integer, public?: true, default: 0
    attribute :pending, :integer, public?: true, default: 0
    attribute :rejected, :integer, public?: true, default: 0
    attribute :skipped, :integer, public?: true, default: 0
  end

  graphql do
    type :task_receipt
  end
end
