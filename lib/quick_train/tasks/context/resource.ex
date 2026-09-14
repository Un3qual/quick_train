defmodule QuickTrain.Tasks.Context.Resource do
  @moduledoc "Read-only collection views of selected canonical fields, without new tables."

  defmacro __using__(opts) do
    source = opts |> Keyword.fetch!(:source) |> Macro.expand(__CALLER__)
    Code.ensure_compiled!(source)

    fields =
      for name <- Keyword.fetch!(opts, :fields), name != :id do
        attribute = Ash.Resource.Info.attribute(source, name)

        options =
          attribute
          |> Map.take([:allow_nil?, :public?, :constraints, :source])
          |> Map.put(:writable?, false)
          |> Map.to_list()

        quote do
          attribute unquote(name), unquote(attribute.type), unquote(Macro.escape(options))
        end
      end

    quote do
      use Ash.Resource,
        primary_read_warning?: false,
        otp_app: :quick_train,
        domain: QuickTrain.Tasks,
        data_layer: AshPostgres.DataLayer,
        authorizers: [Ash.Policy.Authorizer],
        extensions: [AshGraphql.Resource]

      def source_resource, do: unquote(source)

      postgres do
        table unquote(AshPostgres.DataLayer.Info.table(source))
        repo QuickTrain.Repo
        migrate? false
      end

      attributes do
        uuid_primary_key :id
        unquote_splicing(fields)
      end

      actions do
        read :read do
          primary? true
          prepare build(sort: unquote(Keyword.fetch!(opts, :sort)))

          pagination keyset?: true,
                     required?: false,
                     default_limit: 50,
                     max_page_size: 100,
                     stable_sort: unquote(Keyword.fetch!(opts, :sort))
        end

        if unquote(Keyword.fetch!(opts, :definition?)) do
          read :get_task_definition do
            transaction? true
            get? true
            argument :organization_id, :uuid, allow_nil?: false
            argument :project_id, :uuid, allow_nil?: false
            argument :id, :uuid, allow_nil?: false
            argument :attempt_id, :uuid
            filter expr(^ref(:id) == ^arg(:id))
            prepare QuickTrain.Tasks.Access.ContractAccess.DefinitionRead
          end
        end
      end

      policies do
        policy action_type(:read) do
          authorize_if QuickTrain.Tasks.Access.ContractAccess
        end
      end
    end
  end
end
