defmodule QuickTrain.Forms.NestedRead do
  @moduledoc false
  use Ash.Policy.FilterCheck
  alias QuickTrain.Authorization
  alias QuickTrain.Organizations.Membership

  @impl true
  def describe(_opts),
    do: "nested definitions belong to an organization the actor can inspect or manage"

  @impl true
  def filter(%{id: user_id, status: "active"}, _context, opts) do
    organization_ids =
      Membership
      |> Ash.Query.filter(user_id == ^user_id and status == "active")
      |> Ash.Query.select([:organization_id])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.organization_id)
      |> Enum.filter(fn id ->
        Authorization.allowed?(user_id, id, "forms.read") or
          Authorization.allowed?(user_id, id, "forms.manage")
      end)

    Enum.reduce(
      Enum.reverse(opts[:path]),
      [organization_id: [in: organization_ids]],
      fn relationship, filter -> [{relationship, filter}] end
    )
  rescue
    _error in [
      Ash.Error.Forbidden,
      Ash.Error.Invalid,
      Ash.Error.Framework,
      Ash.Error.Unknown,
      DBConnection.ConnectionError,
      Postgrex.Error
    ] ->
      false
  end

  def filter(_actor, _context, _opts), do: false
end
