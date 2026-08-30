defmodule QuickTrain.Datasets do
  @moduledoc "Organization-owned normalized datasets, revisions, and imports."

  use Ash.Domain, otp_app: :quick_train, extensions: [AshGraphql.Domain]

  resources do
    resource QuickTrain.Datasets.ProductCapabilities do
      define :grant_product_capabilities,
        action: :grant_to_manager,
        args: [:organization_id, :user_id]
    end

    resource QuickTrain.Datasets.Dataset
    resource QuickTrain.Datasets.DatasetFieldDefinition
    resource QuickTrain.Datasets.DatasetRecordType
    resource QuickTrain.Datasets.DatasetSchemaVersion
  end
end
