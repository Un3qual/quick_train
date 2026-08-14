defmodule QuickTrain.Organizations do
  @moduledoc "Enterprise organizations and user memberships."

  alias QuickTrain.Organizations.{Membership, Organization}
  require Ash.Query

  def create_organization(name, slug) do
    Organization
    |> Ash.Changeset.for_create(:create, %{
      name: String.trim(name),
      slug: String.downcase(String.trim(slug))
    })
    |> Ash.create(authorize?: false)
  end

  def add_member(organization_id, user_id) do
    Membership
    |> Ash.Changeset.for_create(:add, %{
      organization_id: organization_id,
      user_id: user_id,
      status: "active"
    })
    |> Ash.create(authorize?: false)
  end

  def member?(organization_id, user_id) do
    Membership
    |> Ash.Query.filter(
      organization_id == ^organization_id and user_id == ^user_id and status == "active"
    )
    |> Ash.exists?(authorize?: false)
  end

  def deactivate_membership(membership_id) do
    with {:ok, membership} <- Ash.get(Membership, membership_id, authorize?: false),
         {:ok, _membership} <-
           membership
           |> Ash.Changeset.for_update(:set_status, %{status: "inactive"})
           |> Ash.update(authorize?: false) do
      :ok
    end
  end
end
