defmodule QuickTrain.Tasks.ExportSelection do
  @moduledoc "Typed immutable evidence membership in one sealed export snapshot."
  use Ash.Resource,
    otp_app: :quick_train,
    domain: QuickTrain.Tasks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false

    attribute :kind, :atom,
      allow_nil?: false,
      constraints: [
        one_of: [
          :task,
          :task_input,
          :attempt,
          :attempt_question,
          :attempt_input_presentation,
          :question_response,
          :static_option_answer,
          :task_input_answer,
          :text_span,
          :review_decision,
          :presentation_element,
          :question_definition,
          :question_option,
          :label,
          :project_input_binding,
          :dataset_value
        ]
      ]

    attribute :record_count, :integer, allow_nil?: false, constraints: [min: 1]
  end

  relationships do
    belongs_to :export, QuickTrain.Tasks.ResultExport, allow_nil?: false
    belongs_to :organization, QuickTrain.Organizations.Organization, allow_nil?: false
    belongs_to :project, QuickTrain.Projects.Project, allow_nil?: false
    belongs_to :form_version, QuickTrain.Forms.FormVersion, allow_nil?: false
    belongs_to :task, QuickTrain.Tasks.Task
    belongs_to :attempt, QuickTrain.Tasks.Attempt
    belongs_to :question, QuickTrain.Forms.Questions.QuestionDefinition
    belongs_to :question_response, QuickTrain.Tasks.QuestionResponse
    belongs_to :decision, QuickTrain.Tasks.ReviewDecision
    belongs_to :presentation_element, QuickTrain.Forms.Presentation.PresentationElement
    belongs_to :question_option, QuickTrain.Forms.Questions.QuestionOption
    belongs_to :label, QuickTrain.Forms.Labels.Label
    belongs_to :binding, QuickTrain.Projects.ProjectInputBinding
    belongs_to :dataset_value, QuickTrain.Datasets.DatasetValue
    belongs_to :revision, QuickTrain.Datasets.DatasetItemRevision
    belongs_to :source_record, QuickTrain.Datasets.DatasetRecord
    belongs_to :field_definition, QuickTrain.Datasets.DatasetFieldDefinition
  end

  actions do
    read :read do
      primary? true

      pagination keyset?: true,
                 required?: false,
                 default_limit: 100,
                 max_page_size: 100,
                 stable_sort: [id: :asc]
    end

    create :create_internal do
      accept [
        :export_id,
        :organization_id,
        :project_id,
        :form_version_id,
        :kind,
        :record_count,
        :task_id,
        :attempt_id,
        :question_id,
        :question_response_id,
        :decision_id,
        :presentation_element_id,
        :question_option_id,
        :label_id,
        :binding_id,
        :dataset_value_id,
        :revision_id,
        :source_record_id,
        :field_definition_id
      ]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  postgres do
    identity_wheres_to_sql source_value: "kind = 'dataset_value'"
    table "export_selections"
    repo QuickTrain.Repo
    migration_defaults id: "fragment(\"gen_random_uuid()\")"
    migration_types record_count: :bigint

    references do
      reference :export,
        on_delete: :restrict,
        match_with: [
          organization_id: :organization_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :organization, on_delete: :restrict

      reference :project,
        on_delete: :restrict,
        match_with: [organization_id: :organization_id, form_version_id: :form_version_id]

      reference :form_version, on_delete: :restrict

      reference :task,
        on_delete: :restrict,
        match_with: [project_id: :project_id, form_version_id: :form_version_id]

      reference :attempt,
        on_delete: :restrict,
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id
        ]

      reference :question, on_delete: :restrict, match_with: [form_version_id: :version_id]

      reference :question_response,
        on_delete: :restrict,
        match_with: [
          task_id: :task_id,
          project_id: :project_id,
          form_version_id: :form_version_id,
          question_id: :question_id
        ]

      reference :decision,
        on_delete: :restrict,
        match_with: [question_response_id: :question_response_id]

      reference :presentation_element,
        on_delete: :restrict,
        match_with: [form_version_id: :version_id]

      reference :question_option,
        on_delete: :restrict,
        match_with: [question_id: :question_id, form_version_id: :version_id]

      reference :label, on_delete: :restrict, match_with: [form_version_id: :version_id]

      reference :binding,
        on_delete: :restrict,
        match_with: [project_id: :project_id, field_definition_id: :field_definition_id]

      reference :dataset_value,
        on_delete: :restrict,
        match_with: [
          organization_id: :organization_id,
          source_record_id: :record_id,
          field_definition_id: :field_definition_id
        ]

      reference :revision,
        on_delete: :restrict,
        match_with: [organization_id: :organization_id, source_record_id: :root_record_id]

      reference :source_record, on_delete: :restrict
      reference :field_definition, on_delete: :restrict
    end

    check_constraints do
      check_constraint :kind, "export_selections_typed_owner",
        check: """
          (kind IN ('task','task_input') AND task_id IS NOT NULL AND num_nonnulls(attempt_id,question_id,question_response_id,decision_id,presentation_element_id,question_option_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind IN ('attempt','attempt_question','attempt_input_presentation') AND task_id IS NOT NULL AND attempt_id IS NOT NULL AND num_nonnulls(question_id,question_response_id,decision_id,presentation_element_id,question_option_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind IN ('question_response','static_option_answer','task_input_answer','text_span','review_decision') AND task_id IS NOT NULL AND question_id IS NOT NULL AND question_response_id IS NOT NULL AND (kind != 'review_decision' OR decision_id IS NOT NULL) AND num_nonnulls(attempt_id,presentation_element_id,question_option_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind = 'presentation_element' AND presentation_element_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_id,question_response_id,decision_id,question_option_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind = 'question_definition' AND question_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_response_id,decision_id,presentation_element_id,question_option_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind = 'question_option' AND question_id IS NOT NULL AND question_option_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_response_id,decision_id,presentation_element_id,label_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind = 'label' AND label_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_id,question_response_id,decision_id,presentation_element_id,question_option_id,binding_id,dataset_value_id,revision_id,source_record_id,field_definition_id) = 0) OR
          (kind = 'project_input_binding' AND binding_id IS NOT NULL AND field_definition_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_id,question_response_id,decision_id,presentation_element_id,question_option_id,label_id,dataset_value_id,revision_id,source_record_id) = 0) OR
          (kind = 'dataset_value' AND binding_id IS NOT NULL AND dataset_value_id IS NOT NULL AND revision_id IS NOT NULL AND source_record_id IS NOT NULL AND field_definition_id IS NOT NULL AND num_nonnulls(task_id,attempt_id,question_id,question_response_id,decision_id,presentation_element_id,question_option_id,label_id) = 0)
        """

      check_constraint :record_count, "export_selections_count_positive",
        check: "record_count > 0"
    end
  end

  identities do
    identity :membership,
             [
               :export_id,
               :kind,
               :task_id,
               :attempt_id,
               :question_id,
               :question_response_id,
               :decision_id,
               :presentation_element_id,
               :question_option_id,
               :label_id,
               :binding_id,
               :dataset_value_id
             ],
             nils_distinct?: false

    identity :source_value, [:export_id, :kind, :dataset_value_id],
      where: expr(kind == :dataset_value)
  end
end
