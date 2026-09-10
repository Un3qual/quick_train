defmodule QuickTrain.Forms.Types.PlainText do
  @moduledoc "UTF-8 text with the ordinary Ash string constraints."
  use Ash.Type.NewType,
    subtype_of: :string,
    constraints: [
      trim?: false,
      allow_empty?: true,
      match: ~r/\A[^\x00]*\z/u,
      length_count: :bytes
    ]

  @impl true
  def cast_input(value, constraints) when is_binary(value) do
    if String.valid?(value), do: super(value, constraints), else: {:error, "must be valid UTF-8"}
  end

  def cast_input(value, constraints), do: super(value, constraints)
end
