defmodule QuickTrain.Forms.Types.FieldCardinality do
  @moduledoc "Closed Forms cardinality values."
  use Ash.Type.Enum, values: [:single]
  def graphql_type(_constraints), do: :form_field_cardinality
end
