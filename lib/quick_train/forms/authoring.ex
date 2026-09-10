defmodule QuickTrain.Forms.Authoring do
  alias Ash.Resource.Info, as: ResourceInfo
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  alias QuickTrain.Forms.{Error, Form, FormVersion, Graph}
  alias QuickTrain.Forms.Presentation.PresentationElement
  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    Ash.transact(FormVersion, fn -> execute(input) end)
  rescue
    error in Ash.Error.Invalid ->
      if Enum.any?(error.errors, &is_struct(&1, Error)),
        do: {:error, error},
        else: Error.invalid(:invalid_definition)

    _error in [Ash.Error.Unknown, Postgrex.Error] ->
      Error.invalid(:invalid_definition)
  end

  defp execute(%{action: %{name: :create_form}, arguments: args}) do
    create(Form, Map.take(args, [:organization_id, :key]))
  end

  defp execute(%{action: %{name: action}, arguments: args})
       when action in [:create_draft, :copy_published] do
    form = locked(Form, organization_id: args.organization_id, id: args.form_id)
    if is_nil(form), do: Error.reject!(:invalid_form)

    source = if action == :copy_published, do: published_source!(form, args.source_version_id)

    number =
      Ash.max!(FormVersion, :version,
        query: [filter: [form_id: form.id]],
        default: 0,
        authorize?: false
      ) + 1

    metadata =
      if source,
        do: Map.take(source, [:title, :description]),
        else: Map.take(args, [:title, :description])

    version = create(FormVersion, Map.merge(metadata, %{form_id: form.id, version: number}))
    if source, do: Graph.copy!(source, version)
    version
  end

  defp execute(input) do
    args = input.arguments

    version =
      locked(FormVersion, id: args.version_id, form: [organization_id: args.organization_id])

    if is_nil(version), do: Error.reject!(:invalid_form_version)

    cond do
      input.action.name == :publish ->
        publish(version)

      version.state != :draft ->
        Error.reject!(:version_not_draft)

      true ->
        result = edit(input, version)
        Graph.validate!(version, :draft)
        result
    end
  end

  defp publish(%{state: :published} = version), do: version

  defp publish(version) do
    Graph.validate!(version, :published)

    version
    |> Ash.Changeset.for_update(:publish_internal, %{}, authorize?: false)
    |> Ash.update!()
  end

  defp edit(%{action: %{name: :update_draft}} = input, version),
    do: update(version, supplied(input, [:title, :description]))

  defp edit(%{action: %{name: :add_to_draft}, resource: resource, arguments: args}, version) do
    if resource == PresentationElement do
      Graph.create_element!(version.id, args)
    else
      create(resource, Map.drop(args, [:organization_id]))
    end
  end

  defp edit(%{action: %{name: :reorder}, resource: resource, arguments: args}, version) do
    for {argument, parent} <- [
          question_id: QuickTrain.Forms.Questions.QuestionDefinition,
          label_set_id: QuickTrain.Forms.Labels.LabelSet
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
    |> Enum.with_index()
    |> Enum.each(fn {id, position} ->
      update(Map.fetch!(by_id, id), %{position: position})
    end)

    true
  end

  defp edit(input, version) do
    record =
      input.resource
      |> Ash.Query.filter(id == ^input.arguments.id and version_id == ^version.id)
      |> Ash.read_one!(authorize?: false)

    if is_nil(record), do: Error.reject!(:invalid_definition)

    case input.action.name do
      :update_in_draft ->
        accepted = ResourceInfo.action(input.resource, :update_internal).accept
        update(record, supplied(input, accepted))

      :remove_from_draft ->
        if input.resource == PresentationElement, do: Graph.remove_element_child!(record)
        Ash.destroy!(record, action: :destroy_internal, authorize?: false)
        true
    end
  end

  defp supplied(input, names) do
    names =
      Enum.filter(
        names,
        &(Map.has_key?(input.params, &1) or Map.has_key?(input.params, to_string(&1)))
      )

    Map.take(input.arguments, names)
  end

  defp locked(resource, filter),
    do:
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

  defp published_source!(form, id) do
    source =
      FormVersion
      |> Ash.Query.filter(id == ^id and form_id == ^form.id and state == :published)
      |> Ash.read_one!(authorize?: false)

    if is_nil(source), do: Error.reject!(:invalid_copy_source)
    source
  end

  def create(resource, attributes),
    do:
      resource
      |> Ash.Changeset.for_create(:create_internal, attributes, authorize?: false)
      |> Ash.create!()

  defp update(record, attributes),
    do:
      record
      |> Ash.Changeset.for_update(:update_internal, attributes, authorize?: false)
      |> Ash.update!()
end
