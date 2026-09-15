defmodule QuickTrain.Projects.Management do
  @moduledoc false
  alias QuickTrain.{Authorization, Projects}
  alias QuickTrain.Projects.Error

  def authorize!(actor, organization_id, capability \\ "projects.manage") do
    unless match?(%{status: "active"}, actor) and
             Authorization.allowed?(actor.id, organization_id, capability),
           do: raise(Ash.Error.Forbidden)
  end

  def lock!(organization_id, project_id) do
    project =
      Projects.lock_project!(organization_id, project_id, authorize?: false)

    if is_nil(project), do: Error.reject!(:invalid_project)
    project
  end
end
