defmodule QuickTrain.Authorization.Checks.OrganizationCapability do
  @moduledoc "Fail-closed organization capability policy check for product actions."

  use Ash.Policy.SimpleCheck

  alias QuickTrain.Authorization

  require Logger

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :capability) do
      {:ok, capability} when is_binary(capability) and capability != "" -> {:ok, opts}
      _other -> {:error, "requires a non-empty :capability option"}
    end
  end

  @impl true
  def describe(opts), do: "actor has #{opts[:capability]} in the action organization"

  @impl true
  def match?(%{id: user_id, status: "active"}, %{subject: subject}, opts) do
    capability = Keyword.get(opts, :capability)
    organization_id = organization_id(subject)

    is_binary(capability) and capability != "" and not is_nil(organization_id) and
      allowed?(user_id, organization_id, capability)
  end

  def match?(_actor, _context, _opts), do: false

  defp organization_id(%Ash.Changeset{} = changeset) do
    Ash.Subject.get_argument_or_attribute(changeset, :organization_id)
  end

  defp organization_id(%Ash.Query{} = query) do
    Ash.Subject.get_argument(query, :organization_id)
  end

  defp organization_id(%Ash.ActionInput{} = input) do
    Ash.Subject.get_argument(input, :organization_id)
  end

  defp organization_id(_subject), do: nil

  defp allowed?(user_id, organization_id, capability) do
    Authorization.allowed?(user_id, organization_id, capability)
  rescue
    _error in [Ash.Error.Forbidden, Ash.Error.Invalid] ->
      false

    error in [
      Ash.Error.Framework,
      Ash.Error.Unknown,
      DBConnection.ConnectionError,
      Postgrex.Error
    ] ->
      Logger.warning(
        "organization capability check failed closed for #{organization_id}: #{inspect(error.__struct__)}"
      )

      false
  end
end
