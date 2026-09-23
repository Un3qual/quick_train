defmodule QuickTrain.Tasks.Access.AttemptOwner do
  @moduledoc false
  use Ash.Policy.SimpleCheck
  alias QuickTrain.Tasks.Access.ReadAccess
  alias QuickTrain.Tasks.Attempts.Attempt
  require Ash.Query

  def describe(_opts), do: "active eligible owner of the scoped attempt"

  def match?(
        %{id: _, status: "active"} = actor,
        %{
          subject: %{
            arguments: %{attempt_id: id, project_id: project_id, organization_id: organization_id}
          }
        },
        _opts
      ) do
    eligibility = ReadAccess.eligible_attempt(actor)

    Attempt
    |> Ash.Query.filter(
      id == ^id and project_id == ^project_id and organization_id == ^organization_id and
        ^eligibility
    )
    |> Ash.exists(authorize?: false)
    |> Kernel.==({:ok, true})
  end

  def match?(_actor, _context, _opts), do: false
end
