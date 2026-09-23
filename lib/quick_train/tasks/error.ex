defmodule QuickTrain.Tasks.Error do
  @moduledoc false
  use Splode.Error, fields: [:category], class: :invalid

  @spec reject!(atom()) :: no_return()
  def reject!(category), do: raise(Ash.Error.Invalid, errors: [exception(category: category)])
  def message(error), do: to_string(error.category)
end

defimpl AshGraphql.Error, for: QuickTrain.Tasks.Error do
  def to_error(error) do
    code = to_string(error.category)
    %{message: code, short_message: code, code: code, fields: [], vars: %{}}
  end
end
