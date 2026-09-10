defmodule QuickTrain.Forms.VersionState do
  @moduledoc "Closed Forms state values."
  use Ash.Type.Enum, values: [:draft, :published]
  def graphql_type(_constraints), do: :form_version_state
end
