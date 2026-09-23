defmodule QuickTrain.Tasks.Access.WorkerEligibility do
  @moduledoc false
  alias QuickTrain.Accounts.User
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.Error
  import Ash.Expr
  require Ash.Query

  def require!(project, user_id) do
    unless eligible?(project, user_id), do: Error.reject!(:forbidden)
    :ok
  end

  def eligible?(_project, nil), do: false

  def eligible?(project, user_id) do
    eligibility = project_filter(user_id)

    Project
    |> Ash.Query.filter(
      id == ^project.id and organization_id == ^project.organization_id and ^eligibility and
        exists(User, id == ^user_id and status == "active")
    )
    |> Ash.exists?(authorize?: false)
  end

  # Allocation and evidence reads share the same audience and revocation rules.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def project_filter(user_id) do
    expr(
      organization.status == "active" and
        not exists(worker_access, user_id == ^user_id and disposition == :block) and
        ((audience in [:organization_members, :both] and
            exists(organization.memberships, user_id == ^user_id and status == "active")) or
           (audience in [:external_users, :both] and
              (external_access == :open or
                 exists(worker_access, user_id == ^user_id and disposition == :allow))))
    )
  end
end
