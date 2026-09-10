defmodule QuickTrain.Forms.Error do
  @moduledoc "Bounded, definition-only Forms validation errors."
  use Splode.Error, fields: [:category, issues: [], truncated: false], class: :invalid

  def invalid(category), do: {:error, exception(category: category)}

  @spec reject!(atom()) :: no_return()
  @spec reject!(atom(), [String.t()]) :: no_return()
  def reject!(category, issues \\ []) do
    raise Ash.Error.Invalid,
      errors: [
        exception(
          category: category,
          issues: Enum.take(issues, 100),
          truncated: Enum.count_until(issues, 101) > 100
        )
      ]
  end

  def message(error) do
    suffix = if error.truncated, do: "; truncated", else: ""
    IO.iodata_to_binary([Enum.join([to_string(error.category) | error.issues], "; "), suffix])
  end
end

defimpl AshGraphql.Error, for: QuickTrain.Forms.Error do
  def to_error(error) do
    %{
      message: QuickTrain.Forms.Error.message(error),
      short_message: to_string(error.category),
      code: to_string(error.category),
      fields: [],
      vars: %{}
    }
  end
end
