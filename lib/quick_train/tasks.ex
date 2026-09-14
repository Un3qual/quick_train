defmodule QuickTrain.Tasks do
  @moduledoc "Scoped collection work, immutable outcomes, review, and result exports."
  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  alias QuickTrain.Tasks.Context

  resources do
    resource Context.ProjectInputBinding
    resource Context.FormVersion
    resource Context.InputSlotDefinition
    resource Context.InputFieldRequirement
    resource Context.PresentationElement
    resource Context.QuestionDefinition
    resource Context.QuestionOption
    resource Context.LabelSet
    resource Context.Label
    resource Context.TextConstraints
    resource Context.IntegerConstraints
    resource Context.DecimalConstraints
    resource Context.SelectionConstraints
    resource Context.AnnotationConstraints
    resource Context.DatasetFieldDefinition
    resource Context.DatasetValue
    resource Context.DatasetValue.Text
    resource Context.DatasetValue.Integer
    resource Context.DatasetValue.Decimal
    resource Context.DatasetValue.Boolean
    resource Context.DatasetValue.DateTime
    resource Context.DatasetValue.Asset
    resource Context.Asset

    resource QuickTrain.Tasks.Task do
      define :reconcile_task, action: :reconcile, args: [:organization_id, :project_id, :task_id]
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
        get_by: [:id, :project_id, :organization_id],
        not_found_error?: false

      define :start_attempt_record, action: :start_record
      define :release_attempt_record, action: :release_record
      define :cancel_attempt_record, action: :cancel_record
      define :expire_attempt_record, action: :expire_record
      define :expire_attempt, action: :expire, args: [:organization_id, :project_id, :attempt_id]
      define :fetch_work, action: :fetch, args: [:organization_id, :project_id, :request_key]

      define :assign_work,
        action: :assign,
        args: [:organization_id, :project_id, :worker_id, :request_key]

      define :assign_follow_up,
        action: :follow_up,
        args: [:organization_id, :project_id, :worker_id, :predecessor_id, :request_key]

      define :start_attempt, action: :start, args: [:organization_id, :project_id, :attempt_id]

      define :release_attempt,
        action: :release,
        args: [:organization_id, :project_id, :attempt_id]

      define :cancel_attempt, action: :cancel, args: [:organization_id, :project_id, :attempt_id]

      define :work_bundle,
        action: :read_work_bundle,
        args: [:organization_id, :project_id, :attempt_id]

      define :attempt_receipt,
        action: :receipt,
        args: [:organization_id, :project_id, :attempt_id]
    end

    resource QuickTrain.Tasks.Attempts.AttemptQuestion
    resource QuickTrain.Tasks.Attempts.AttemptInputPresentation

    resource QuickTrain.Tasks.Progress.TaskQuestionProgress

    resource QuickTrain.Tasks.Progress.TaskItemCoverage do
      define :reconcile_coverage, action: :reconcile, args: [:organization_id, :project_id]
    end

    resource QuickTrain.Tasks.Responses.QuestionResponse
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
      list Context.ProjectInputBinding, :result_input_bindings, :list_result_bindings,
        relay?: true,
        paginate_with: :keyset

      read_one Context.ProjectInputBinding, :result_input_binding, :get_result_binding

      read_one Context.FormVersion, :task_form_version, :get_task_definition
      read_one Context.InputSlotDefinition, :task_input_slot_definition, :get_task_definition
      read_one Context.InputFieldRequirement, :task_input_field_requirement, :get_task_definition
      read_one Context.PresentationElement, :task_presentation_element, :get_task_definition
      read_one Context.QuestionDefinition, :task_question_definition, :get_task_definition
      read_one Context.QuestionOption, :task_question_option, :get_task_definition
      read_one Context.LabelSet, :task_label_set, :get_task_definition
      read_one Context.Label, :task_label, :get_task_definition
      read_one Context.TextConstraints, :task_text_constraints, :get_task_definition
      read_one Context.IntegerConstraints, :task_integer_constraints, :get_task_definition
      read_one Context.DecimalConstraints, :task_decimal_constraints, :get_task_definition
      read_one Context.SelectionConstraints, :task_selection_constraints, :get_task_definition
      read_one Context.AnnotationConstraints, :task_annotation_constraints, :get_task_definition
      read_one Context.DatasetFieldDefinition, :task_field_definition, :get_task_definition

      for {resource, singular, plural} <- [
            {QuickTrain.Tasks.Task, :task, :tasks},
            {QuickTrain.Tasks.Progress.TaskQuestionProgress, :task_progress, :task_progress_rows},
            {QuickTrain.Tasks.Progress.TaskItemCoverage, :task_item_coverage,
             :task_item_coverage_rows},
            {QuickTrain.Tasks.TaskInput, :task_input, :task_inputs},
            {QuickTrain.Tasks.Attempts.Attempt, :attempt, :attempts},
            {QuickTrain.Tasks.Attempts.AttemptQuestion, :attempt_question, :attempt_questions},
            {QuickTrain.Tasks.Attempts.AttemptInputPresentation, :attempt_input_presentation,
             :attempt_input_presentations},
            {QuickTrain.Tasks.Responses.QuestionResponse, :question_response,
             :question_responses},
            {QuickTrain.Tasks.Responses.StaticOptionAnswer, :static_option_answer,
             :static_option_answers},
            {QuickTrain.Tasks.Responses.TaskInputAnswer, :task_input_answer, :task_input_answers},
            {QuickTrain.Tasks.Responses.TextSpan, :text_span, :text_spans},
            {QuickTrain.Tasks.Reviews.ReviewDecision, :review_decision, :review_decisions}
          ] do
        list resource, :"audit_#{plural}", :list_audit, relay?: true, paginate_with: :keyset
        read_one resource, :"audit_#{singular}", :get_audit
        list resource, :"accepted_#{plural}", :list_accepted, relay?: true, paginate_with: :keyset
        read_one resource, :"accepted_#{singular}", :get_accepted
      end

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

      action QuickTrain.Tasks.Attempts.Attempt, :assign_follow_up, :follow_up,
        args: [:organization_id, :project_id, :worker_id, :predecessor_id, :request_key]

      action QuickTrain.Tasks.Attempts.Attempt, :start_attempt, :start,
        args: [:organization_id, :project_id, :attempt_id]

      action QuickTrain.Tasks.Attempts.Attempt, :release_attempt, :release,
        args: [:organization_id, :project_id, :attempt_id]

      action QuickTrain.Tasks.Attempts.Attempt, :cancel_attempt, :cancel,
        args: [:organization_id, :project_id, :attempt_id]

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
          :mode,
          :task_id_from,
          :task_id_to,
          :evidence_kind,
          :evidence_id_from,
          :evidence_id_to
        ]
    end
  end
end
