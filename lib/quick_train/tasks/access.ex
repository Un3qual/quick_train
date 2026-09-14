defmodule QuickTrain.Tasks.Access do
  @moduledoc false
  alias QuickTrain.Projects.Project
  alias QuickTrain.Tasks.{Attempt, Error, Leases, Response, Task, WorkerEligibility}
  require Ash.Query

  def project!(organization_id, project_id, lock \\ "FOR SHARE") do
    Project
    |> Ash.Query.filter(id == ^project_id and organization_id == ^organization_id)
    |> Ash.Query.lock(lock)
    |> Ash.read_one!(authorize?: false)
    |> found!()
  end

  def manager!(project, %{id: id}, capability) do
    unless QuickTrain.Authorization.allowed?(id, project.organization_id, capability),
      do: Error.reject!(:forbidden)
  end

  def manager!(_project, _actor, _capability), do: Error.reject!(:forbidden)

  def lock_attempt!(project, attempt_id) do
    initial =
      Attempt
      |> Ash.Query.filter(id == ^attempt_id and project_id == ^project.id)
      |> Ash.read_one!(authorize?: false)
      |> found!()

    task =
      Task
      |> Ash.Query.filter(id == ^initial.task_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    attempt =
      Attempt
      |> Ash.Query.filter(id == ^initial.id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

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

  def response!(attempt) do
    Response
    |> Ash.Query.filter(attempt_id == ^attempt.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> found!()
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
