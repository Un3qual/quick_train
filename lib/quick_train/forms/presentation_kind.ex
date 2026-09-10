defmodule QuickTrain.Forms.PresentationKind do
  @moduledoc "Closed Forms kind values."
  use Ash.Type.Enum, values: [:instruction, :heading, :section, :bound_value, :question]
  def graphql_type(_constraints), do: :form_presentation_kind
end
