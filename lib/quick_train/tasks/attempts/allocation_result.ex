defmodule QuickTrain.Tasks.Attempts.AllocationResult do
  @moduledoc false
  use Ash.Resource,
    otp_app: :quick_train,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  attributes do
    attribute :status, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [
        one_of: [
          :issued,
          :retry_later,
          :waiting_for_answers,
          :no_work_for_worker
        ]
      ]

    attribute :attempt, :struct,
      public?: true,
      writable?: false,
      constraints: [instance_of: Module.concat(["QuickTrain.Tasks.Attempts.Attempt"])]
  end

  graphql do
    type :task_allocation_result
  end
end
