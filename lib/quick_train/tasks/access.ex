defmodule QuickTrain.Tasks.Access do
  @moduledoc false
  alias QuickTrain.{Projects, Tasks}
  alias QuickTrain.Tasks.Access.WorkerEligibility
  alias QuickTrain.Tasks.Attempts.Leases
  alias QuickTrain.Tasks.Error

  def project!(organization_id, project_id, lock \\ "FOR SHARE") do
    Projects.get_project!(organization_id, project_id,
      query: [lock: lock],
      not_found_error?: false,
      authorize?: false
    )
    |> found!()
  end

  def manager!(project, %{id: id}, capability) do
    unless QuickTrain.Authorization.allowed?(id, project.organization_id, capability),
      do: Error.reject!(:forbidden)
  end

  def manager!(_project, _actor, _capability), do: Error.reject!(:forbidden)

  def lock_attempt!(project, attempt_id) do
    initial =
      Tasks.get_attempt_internal!(attempt_id, project.id, project.organization_id,
        authorize?: false
      )
      |> found!()

    task =
      Tasks.get_task_internal!(initial.task_id, project.id, project.organization_id,
        query: [lock: :for_update],
        authorize?: false
      )
      |> found!()

    attempt =
      Tasks.get_attempt_internal!(initial.id, project.id, project.organization_id,
        query: [lock: :for_update],
        authorize?: false
      )
      |> found!()

    {task, attempt}
  end

  def owner!(project, attempt, %{id: user_id}, live? \\ true) do
    if attempt.worker_id != user_id, do: Error.reject!(:forbidden)
    WorkerEligibility.require!(project, user_id)

    if live? do
      unless project.state in [:active, :paused], do: Error.reject!(:project_closed)
      unless attempt.state in Leases.live_states(), do: Error.reject!(:attempt_terminal)

      if DateTime.compare(attempt.deadline, Leases.now!()) != :gt,
        do: Error.reject!(:attempt_expired)
    end

    :ok
  end

  def scope(project),
    do: %{
      organization_id: project.organization_id,
      project_id: project.id,
      form_version_id: project.form_version_id
    }

  def found!(nil), do: Error.reject!(:forbidden)
  def found!(record), do: record
end
