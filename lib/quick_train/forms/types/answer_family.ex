defmodule QuickTrain.Forms.Types.AnswerFamily do
  @moduledoc "Closed Forms family values."
  use Ash.Type.Enum,
    values: [
      :text,
      :integer,
      :decimal,
      :boolean,
      :static_single_choice,
      :static_multiple_choice,
      :task_input_single_choice,
      :task_input_multiple_choice,
      :task_input_ranking,
      :bounding_boxes,
      :polygon_regions,
      :raster_masks,
      :text_spans
    ]

  def graphql_type(_constraints), do: :form_answer_family
end
