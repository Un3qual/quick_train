defmodule QuickTrain.Forms.Renderer do
  @moduledoc "Closed Forms renderer values."
  use Ash.Type.Enum,
    values: [
      :text_input,
      :text_area,
      :integer_input,
      :stars,
      :likert,
      :decimal_input,
      :checkbox,
      :toggle,
      :radio,
      :dropdown,
      :checkbox_group,
      :pairwise,
      :image_choice,
      :ranking,
      :bounding_boxes,
      :polygon_regions,
      :raster_masks,
      :text_spans
    ]

  def graphql_type(_constraints), do: :form_renderer
end
