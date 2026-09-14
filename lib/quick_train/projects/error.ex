defmodule QuickTrain.Projects.Error do
  @moduledoc false
  use Splode.Error, fields: [:category, issues: []], class: :invalid

  @spec reject!(atom()) :: no_return()
  @spec reject!(atom(), [String.t()]) :: no_return()
  def reject!(category, issues \\ []) do
    raise Ash.Error.Invalid, errors: [exception(category: category, issues: issues)]
  end

  def message(error), do: Enum.join([to_string(error.category) | error.issues], "; ")
end

defimpl AshGraphql.Error, for: QuickTrain.Projects.Error do
  def to_error(error) do
    %{
      message: QuickTrain.Projects.Error.message(error),
      short_message: to_string(error.category),
      code: to_string(error.category),
      fields: [],
      vars: %{}
    }
  end
end
