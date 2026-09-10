defmodule QuickTrain.Forms.Types.PlainText do
  @moduledoc "Text with shared Ash string constraints."
  use Ash.Type.NewType,
    subtype_of: :string,
    constraints: [
      trim?: false,
      allow_empty?: true,
      length_count: :bytes
    ]
end
