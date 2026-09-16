defmodule QuickTrain.Assets.Asset.Changes.PrepareStaging do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    # Staging access needs the UUID before Ash evaluates lazy create defaults.
    changeset = Ash.Changeset.change_new_attribute_lazy(changeset, :id, &Ash.UUID.generate/0)
    id = Ash.Changeset.get_attribute(changeset, :id)
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    lifetime =
      Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:staging_lifetime_seconds)

    changeset
    |> Ash.Changeset.change_new_attribute(:staging_key, "assets/staging/#{organization_id}/#{id}")
    |> Ash.Changeset.change_new_attribute(
      :staging_expires_at,
      DateTime.add(DateTime.utc_now(), lifetime, :second)
    )
  end
end
