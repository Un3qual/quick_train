defmodule QuickTrain.Accounts.Session.Changes.SetTimestamps do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    now = DateTime.utc_now()

    Ash.Changeset.force_change_attributes(changeset, %{
      issued_at: now,
      expires_at: DateTime.add(now, 8, :hour)
    })
  end
end
