defmodule QuickTrain.Forms.Authoring do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Forms
  alias QuickTrain.Forms.{Error, FormVersion, Graph}
  alias QuickTrain.Forms.Labels.LabelSet
  alias QuickTrain.Forms.Questions.QuestionDefinition
  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    {:ok, execute(input)}
  rescue
    error in [Ash.Error.Invalid, Ash.Error.Unknown, Postgrex.Error] -> {:error, error}
  end

  defp execute(%{action: %{name: :copy_published}, arguments: args}) do
    form = Forms.lock_form!(args.form_id, args.organization_id, authorize?: false)
    if is_nil(form), do: Error.reject!(:invalid_form)
    source = published_source!(form, args.source_version_id)

    version =
      Forms.create_form_draft!(
        args.organization_id,
        Map.take(source, [:title, :description]) |> Map.put(:form_id, form.id),
        authorize?: false
      )

    Graph.copy!(source, version)
    version
  end

  defp execute(input) do
    args = input.arguments

    version =
      Forms.lock_form_version!(args.version_id, args.organization_id, authorize?: false)

    if is_nil(version), do: Error.reject!(:invalid_form_version)

    cond do
      input.action.name == :publish ->
        publish(version)

      version.state != :draft ->
        Error.reject!(:version_not_draft)

      true ->
        edit(input, version)
    end
  end

  defp publish(%{state: :published} = version), do: version

  defp publish(version) do
    Graph.validate!(version, :published)

    Ash.update!(version, %{}, action: :publish_internal, authorize?: false)
  end

  defp edit(%{action: %{name: :reorder}, resource: resource, arguments: args}, version) do
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
      return_records?: true
    )

    true
  end

  defp published_source!(form, id) do
    source =
      FormVersion
      |> Ash.Query.filter(id == ^id and form_id == ^form.id and state == :published)
      |> Ash.read_one!(authorize?: false)

    if is_nil(source), do: Error.reject!(:invalid_copy_source)
    source
  end
end
