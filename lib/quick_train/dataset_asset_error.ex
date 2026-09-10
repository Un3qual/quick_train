defmodule QuickTrain.DatasetAssetError do
  @moduledoc "Expected asset and dataset lifecycle failures shared by Ash and GraphQL."

  use Splode.Error, fields: [:category, :detail], class: :invalid

  def invalid(category), do: {:error, exception(category: category)}

  def wrap({:error, category}) when is_atom(category), do: invalid(category)

  def wrap({:error, "required_missing:" <> fields}) do
    {:error, exception(category: :required_missing, detail: fields)}
  end

  def wrap(result), do: result

  def message(error), do: public_message(error)

  def public_message(%{category: category, detail: nil}), do: Atom.to_string(category)
  def public_message(%{category: category, detail: detail}), do: "#{category}:#{detail}"
end

defimpl AshGraphql.Error, for: QuickTrain.DatasetAssetError do
  def to_error(error) do
    %{
      message: QuickTrain.DatasetAssetError.public_message(error),
      short_message: Atom.to_string(error.category),
      code: Atom.to_string(error.category),
      fields: [],
      vars: %{}
    }
  end
end
