defmodule QuickTrain.Forms.Reorder do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Forms
  alias QuickTrain.Forms.Error
  alias QuickTrain.Forms.Labels.LabelSet
  alias QuickTrain.Forms.Questions.QuestionDefinition
  require Ash.Query

  @impl true
  def run(%{resource: resource, arguments: args}, _opts, _context) do
    version =
      Forms.lock_form_version!(args.version_id, args.organization_id, authorize?: false)

    if is_nil(version), do: Error.reject!(:invalid_form_version)

    if version.state != :draft, do: Error.reject!(:version_not_draft)
    reorder(resource, args, version)
    {:ok, true}
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Unknown, Postgrex.Error] -> {:error, error}
  end

  defp reorder(resource, args, version) do
    for {argument, parent} <- [
          question_id: QuestionDefinition,
          label_set_id: LabelSet
        ],
        Map.has_key?(args, argument) do
      id = Map.fetch!(args, argument)

      unless parent
             |> Ash.Query.filter(id == ^id and version_id == ^version.id)
             |> Ash.exists?(authorize?: false),
             do: Error.reject!(:invalid_definition)
    end

    filter =
      Map.take(args, [:question_id, :label_set_id])
      |> Map.put(:version_id, version.id)
      |> Map.to_list()

    records = resource |> Ash.Query.filter(^filter) |> Ash.read!(authorize?: false, page: false)
    ids = args.ids

    unless length(ids) == length(records) and MapSet.new(ids) == MapSet.new(records, & &1.id),
      do: Error.reject!(:invalid_permutation)

    by_id = Map.new(records, &{&1.id, &1})

    ids
    |> Enum.with_index(fn id, position -> {Map.fetch!(by_id, id), %{position: position}} end)
    |> Ash.update_many!(resource, :update_internal,
      authorize?: false,
      strategy: [:atomic],
      return_records?: false
    )
  end
end
