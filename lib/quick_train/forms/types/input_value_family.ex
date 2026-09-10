defmodule QuickTrain.Forms.Types.InputValueFamily do
  @moduledoc "Closed Forms value family values."
  use Ash.Type.Enum, values: [:text, :integer, :decimal, :boolean, :utc_datetime, :asset]
  def graphql_type(_constraints), do: :form_input_value_family
end
