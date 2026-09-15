defmodule QuickTrain.Tasks do
  @moduledoc "Scoped collection work, immutable outcomes, review, and result exports."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Tasks.Task do
      define :list_tasks, action: :list_scoped, args: [:organization_id, :project_id]
      define :get_task, action: :get_scoped, args: [:organization_id, :project_id, :id]
    end

    resource QuickTrain.Tasks.TaskInput do
      define :bound_value, action: :bound_value, args: [:organization_id, :project_id]
      define :source_download, action: :source_download, args: [:organization_id, :project_id]
    end

    resource QuickTrain.Tasks.Attempts.Attempt do
      define :revise_attempt, action: :revise

      define :save_question,
        action: :save_question,
        args: [:organization_id, :project_id, :attempt_id]

      define :submit_response, action: :submit, args: [:organization_id, :project_id, :attempt_id]

      define :get_attempt_internal,
        action: :read,
        get_by: [:id, :project_id, :organization_id]

      define :start_attempt, action: :start
      define :release_attempt, action: :release
      define :cancel_attempt, action: :cancel
      define :expire_attempt, action: :expire
      define :fetch_work, action: :fetch, args: [:organization_id, :project_id, :request_key]

      define :assign_work,
        action: :assign,
        args: [:organization_id, :project_id, :worker_id, :request_key]

      define :work_bundle,
        action: :read_work_bundle,
        args: [:organization_id, :project_id, :attempt_id]

      define :attempt_receipt,
        action: :receipt,
        args: [:organization_id, :project_id, :attempt_id]
    end

    resource QuickTrain.Tasks.Attempts.AttemptInputPresentation

    resource QuickTrain.Tasks.Responses.QuestionResponse do
      define :list_task_results, action: :list_scoped, args: [:organization_id, :project_id]
      define :get_task_result, action: :get_scoped, args: [:organization_id, :project_id, :id]
    end

    resource QuickTrain.Tasks.Responses.StaticOptionAnswer
    resource QuickTrain.Tasks.Responses.TaskInputAnswer
    resource QuickTrain.Tasks.Responses.TextSpan

    resource QuickTrain.Tasks.Reviews.ReviewDecision do
      define :decide_question, action: :decide, args: [:organization_id, :project_id]

      define :review_questions,
        action: :review_batch,
        args: [:organization_id, :project_id, :decisions]
    end

    resource QuickTrain.Tasks.Exports.ResultExport do
      define :process_result_export, action: :process, args: [:id]
      define :seal_export_snapshot, action: :seal_snapshot, args: [:id]

      define :request_result_export,
        action: :request_export,
        args: [:organization_id, :project_id, :request_key, :mode]

      define :list_result_exports, action: :list_scoped, args: [:organization_id, :project_id]

      define :get_result_export,
        action: :get_scoped,
        args: [:organization_id, :project_id, :export_id]

      define :result_export_download,
        action: :download_export,
        args: [:organization_id, :project_id, :export_id]
    end

    resource QuickTrain.Tasks.Exports.ExportSelection
  end

  graphql do
    queries do
      list QuickTrain.Tasks.Task, :tasks, :list_scoped, relay?: true, paginate_with: :keyset
      read_one QuickTrain.Tasks.Task, :task, :get_scoped

      list QuickTrain.Tasks.Responses.QuestionResponse, :task_results, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      read_one QuickTrain.Tasks.Responses.QuestionResponse, :task_result, :get_scoped

      action QuickTrain.Tasks.Attempts.Attempt, :work_bundle, :work_bundle

      action QuickTrain.Tasks.Attempts.Attempt, :attempt_receipt, :receipt

      action QuickTrain.Tasks.TaskInput, :task_bound_value, :bound_value

      action QuickTrain.Tasks.TaskInput, :task_source_download, :source_download

      list QuickTrain.Tasks.Exports.ResultExport, :result_exports, :list_scoped,
        relay?: true,
        paginate_with: :keyset

      read_one QuickTrain.Tasks.Exports.ResultExport, :result_export, :get_scoped

      action QuickTrain.Tasks.Exports.ResultExport, :result_export_download, :download_export
    end

    mutations do
      action QuickTrain.Tasks.Attempts.Attempt, :fetch_work, :fetch,
        args: [:organization_id, :project_id, :request_key]

      action QuickTrain.Tasks.Attempts.Attempt, :assign_work, :assign,
        args: [:organization_id, :project_id, :worker_id, :request_key]

      update QuickTrain.Tasks.Attempts.Attempt, :start_attempt, :start,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Tasks.Attempts.Attempt, :release_attempt, :release,
        read_action: :get_for_update,
        identity: false

      update QuickTrain.Tasks.Attempts.Attempt, :cancel_attempt, :cancel,
        read_action: :get_for_update,
        identity: false

      action QuickTrain.Tasks.Attempts.Attempt, :save_task_question, :save_question,
        args: [
          :organization_id,
          :project_id,
          :attempt_id,
          :question_id,
          :expected_revision,
          :answer
        ]

      action QuickTrain.Tasks.Attempts.Attempt, :submit_task_response, :submit,
        args: [:organization_id, :project_id, :attempt_id]

      action QuickTrain.Tasks.Reviews.ReviewDecision, :decide_task_question, :decide,
        args: [
          :organization_id,
          :project_id,
          :question_response_id,
          :request_key,
          :expected_predecessor_id,
          :verdict,
          :reason
        ]

      action QuickTrain.Tasks.Reviews.ReviewDecision, :review_task_questions, :review_batch,
        args: [:organization_id, :project_id, :decisions]

      action QuickTrain.Tasks.Exports.ResultExport, :request_result_export, :request_export,
        args: [
          :organization_id,
          :project_id,
          :request_key,
          :mode
        ]
    end
  end
end
