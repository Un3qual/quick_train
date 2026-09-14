defmodule QuickTrain.Tasks.Access.WorkerEligibility do
  @moduledoc false
  alias QuickTrain.Accounts.User
  alias QuickTrain.Organizations.{Membership, Organization}
  alias QuickTrain.Projects.ProjectWorkerAccess
  alias QuickTrain.Tasks.Error
  require Ash.Query

  def require!(project, user_id) do
    unless eligible?(project, user_id), do: Error.reject!(:forbidden)
    :ok
  end

  def eligible?(_project, nil), do: false

  def eligible?(project, user_id) do
    with %{status: "active"} <-
           Ash.get!(User, user_id, authorize?: false, not_found_error?: false),
         %{status: "active"} <-
           Ash.get!(Organization, project.organization_id,
             authorize?: false,
             not_found_error?: false
           ) do
      access =
        ProjectWorkerAccess
        |> Ash.Query.filter(project_id == ^project.id and user_id == ^user_id)
        |> Ash.read_one!(authorize?: false)

      member? =
        project.audience in [:organization_members, :both] and
          Membership
          |> Ash.Query.filter(
            organization_id == ^project.organization_id and user_id == ^user_id and
              status == "active"
          )
          |> Ash.exists?(authorize?: false)

      external? =
        project.audience in [:external_users, :both] and
          (project.external_access == :open or match?(%{disposition: :allow}, access))

      not match?(%{disposition: :block}, access) and (member? or external?)
    else
      _ -> false
    end
  end
end
