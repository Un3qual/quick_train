defmodule QuickTrain.Tasks.Exports.ResultExporting do
  alias QuickTrain.Accounts.User
  alias QuickTrain.Assets
  alias QuickTrain.Assets.Asset
  alias QuickTrain.Assets.AssetAccessResult
  alias QuickTrain.Assets.Storage
  alias QuickTrain.DatasetAssetError
  alias QuickTrain.Tasks
  alias QuickTrain.Tasks.{Access, Error}
  alias QuickTrain.Tasks.Exports.{Jsonl, ResultExport}
  alias QuickTrain.Tasks.Workers.ExportResults
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  require Ash.Query

  @impl true
  def run(%{action: %{name: :process}, arguments: %{id: id}}, _opts, _context),
    do: process(id) |> DatasetAssetError.wrap()

  def run(%{action: %{name: :request_export}} = input, _opts, context) do
    args = input.arguments

    Ash.transact(ResultExport, fn ->
      project = Access.project!(args.organization_id, args.project_id)
      Access.manager!(project, context.actor, "tasks.results.read")
      # A requester row serializes request-key retries before the unique insert;
      # enqueue and export identity commit together.
      User
      |> Ash.Query.filter(id == ^context.actor.id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

      existing =
        ResultExport
        |> Ash.Query.filter(
          project_id == ^project.id and requester_id == ^context.actor.id and
            request_key == ^args.request_key
        )
        |> Ash.read_one!(authorize?: false)

      if existing do
        same_request!(existing, args)
      else
        require_activated!(project)

        attrs =
          Map.merge(args, %{
            requester_id: context.actor.id,
            form_version_id: project.form_version_id
          })

        export = Ash.create!(ResultExport, attrs, action: :create_internal, authorize?: false)
        %{id: export.id} |> ExportResults.new() |> Oban.insert!()
        export
      end
    end)
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  def run(%{action: %{name: :download_export}} = input, _opts, context) do
    args = input.arguments

    with {:ok, asset} <-
           Ash.transact(ResultExport, fn ->
             project = Access.project!(args.organization_id, args.project_id)
             Access.manager!(project, context.actor, "tasks.results.read")

             export =
               ResultExport
               |> Ash.Query.filter(
                 id == ^args.export_id and project_id == ^project.id and
                   organization_id == ^project.organization_id
               )
               |> Ash.read_one!(authorize?: false)
               |> Access.found!()

             ready_asset!(export)
           end),
         {:ok, access} <- read_access(asset) do
      {:ok, AssetAccessResult.from(asset, access)}
    else
      {:error, reason} when is_atom(reason) -> DatasetAssetError.wrap({:error, reason})
      error -> error
    end
  rescue
    error in Ash.Error.Invalid -> {:error, error}
  end

  defp require_activated!(%{state: state})
       when state in [:active, :paused, :completed, :archived], do: :ok

  defp require_activated!(_project), do: Error.reject!(:project_not_activated)

  defp same_request!(existing, args) do
    unless existing.mode == args.mode,
      do: Error.reject!(:export_request_conflict)

    existing
  end

  defp ready_asset!(%{state: :ready, asset_id: id, organization_id: organization_id}),
    do: Assets.get_asset!(id, organization_id, authorize?: false)

  defp ready_asset!(_export), do: Error.reject!(:export_not_ready)

  defp process(id) do
    {:ok, export} =
      Ash.transact(ResultExport, fn ->
        export = locked_export!(id)

        if is_nil(export.snapshot_at) and export.state != :ready,
          do:
            Ash.update!(export, %{state: :snapshotting},
              action: :update_internal,
              authorize?: false
            ),
          else: export
      end)

    if export.state == :ready do
      :ok
    else
      case Tasks.seal_export_snapshot(id, authorize?: false) do
        {:ok, snapshot} -> publish(snapshot)
        {:error, _error} -> fail(id, :export_snapshot_failed)
      end
    end
  rescue
    # reach:disable-next-line bare_rescue -- Oban errors must not contain answer or provider exception details.
    _error -> fail(id, :export_failed)
  end

  defp publish(export) do
    path =
      Path.join(
        System.tmp_dir!(),
        "quick_train_export_#{export.id}_#{System.unique_integer([:positive])}.jsonl"
      )

    try do
      facts = Jsonl.write!(export, path)

      with {:ok, asset} <- pending_asset(export, facts),
           :ok <- write(asset, path),
           {:ok, _result} <-
             Assets.finalize_asset(asset.id, asset.organization_id, authorize?: false),
           {:ok, canonical} <-
             Assets.get_accessible_asset_internal(asset.id, asset.organization_id,
               authorize?: false
             ),
           true <- not is_nil(canonical),
           {:ok, ^facts} <-
             Storage.verify_sealed(canonical.sealed_key, facts, config(:publication_deadline_ms)),
           {:ok, _access} <- read_access(canonical),
           {:ok, _export} <-
             Ash.transact(ResultExport, fn ->
               current = locked_export!(export.id)

               Ash.update!(current, %{state: :ready, asset_id: canonical.id, error_code: nil},
                 action: :update_internal,
                 authorize?: false
               )
             end) do
        :ok
      else
        {:error, reason} when is_atom(reason) -> fail(export.id, reason)
        _error -> fail(export.id, :export_publication_failed)
      end
    after
      File.rm(path)
    end
  end

  defp pending_asset(export, facts) do
    Ash.transact([ResultExport, Asset], fn ->
      current = locked_export!(export.id)

      pending_asset!(current, facts)
    end)
  end

  defp pending_asset!(export, facts) do
    if export.pending_asset_id do
      asset =
        Assets.get_asset!(export.pending_asset_id, export.organization_id, authorize?: false)

      unless Map.take(asset, [:sha256, :byte_size, :media_type]) == facts,
        do: Error.reject!(:export_snapshot_mismatch)

      if asset.state in [:pending, :failed] and
           DateTime.compare(asset.staging_expires_at, DateTime.utc_now()) != :gt,
         do: create_pending_asset!(export, facts),
         else: asset
    else
      create_pending_asset!(export, facts)
    end
  end

  defp create_pending_asset!(export, facts) do
    asset =
      Assets.create_pending_asset!(
        Map.merge(facts, %{organization_id: export.organization_id, result_export_id: export.id}),
        authorize?: false
      )

    Ash.update!(export, %{pending_asset_id: asset.id},
      action: :update_internal,
      authorize?: false
    )

    asset
  end

  defp write(%{state: state}, _path) when state in [:ready, :duplicate_content], do: :ok

  defp write(asset, path) do
    if DateTime.compare(asset.staging_expires_at, DateTime.utc_now()) != :gt do
      {:error, :staging_expired}
    else
      case Storage.write_staging(
             asset.staging_key,
             File.stream!(path, 64 * 1024, []),
             config(:max_bytes),
             config(:publication_deadline_ms)
           ) do
        {:error, :staging_fenced} -> :ok
        result -> result
      end
    end
  end

  defp read_access(asset) do
    case Storage.sealed_read_access(
           asset.sealed_key,
           DateTime.add(DateTime.utc_now(), config(:read_access_lifetime_seconds), :second)
         ) do
      {:ok, access} -> {:ok, access}
      _unavailable -> {:error, :export_access_unavailable}
    end
  rescue
    # reach:disable-next-line bare_rescue -- Public downloads must not expose provider exception details.
    _error -> {:error, :export_access_unavailable}
  catch
    _kind, _reason -> {:error, :export_access_unavailable}
  end

  defp config(key), do: Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(key)

  defp fail(id, reason) do
    # Reasons are closed atoms from this workflow/storage contract; never persist
    # exception text, provider details, or serialized answer content.
    Ash.transact(ResultExport, fn ->
      export = locked_export!(id)

      if export.state != :ready,
        do:
          Ash.update!(export, %{state: :failed, error_code: Atom.to_string(reason)},
            action: :update_internal,
            authorize?: false
          )
    end)

    {:error, reason}
  rescue
    # reach:disable-next-line bare_rescue -- Failure persistence errors must also be sanitized for Oban.
    _error -> {:error, :export_failed}
  end

  defp locked_export!(id) do
    Tasks.get_result_export_internal!(id,
      query: [lock: :for_update],
      authorize?: false
    )
    |> Access.found!()
  end
end
