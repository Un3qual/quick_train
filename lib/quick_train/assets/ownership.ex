defmodule QuickTrain.Assets.Ownership do
  @moduledoc false
  require Ash.Query
  alias QuickTrain.Assets.Asset

  # Knowing an export's digest or ID is not proof of independently owned bytes.
  # Only a verified ordinary upload (including a deduplicated upload) is proof.
  def independent_query(query) do
    Ash.Query.filter(
      query,
      is_nil(result_export_id) or
        exists(duplicate_assets, is_nil(result_export_id) and state == :duplicate_content)
    )
  end

  def require_independent(_id, %{authorize?: false}), do: :ok

  def require_independent(id, _context) do
    if Asset
       |> Ash.Query.filter(id == ^id)
       |> independent_query()
       |> Ash.exists?(authorize?: false),
       do: :ok,
       else: {:error, :asset_not_found}
  end
end
