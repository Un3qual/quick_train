defmodule QuickTrain.Assets.Storage.S3.Qualification do
  @moduledoc "Explicit qualification of the configured AWS bucket and application identity."

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  alias ExAws.S3, as: SDK
  alias QuickTrain.Assets.Storage.S3
  alias QuickTrain.Assets.Storage.S3.{Config, HTTPClient, Operation}

  @request_budget 10_000
  @absent_codes %{
    object_lock: "ObjectLockConfigurationNotFoundError",
    replication: "ReplicationConfigurationNotFoundError"
  }

  def cli do
    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, _} = Application.ensure_all_started(:ex_aws)

    options = [
      access_key_id: System.get_env("QUICK_TRAIN_STORAGE_CHECK_ACCESS_KEY"),
      secret_access_key: System.get_env("QUICK_TRAIN_STORAGE_CHECK_SECRET_KEY"),
      security_token: System.get_env("QUICK_TRAIN_STORAGE_CHECK_SESSION_TOKEN")
    ]

    {status, report} = run(options)
    IO.puts(Jason.encode!(report, pretty: true))
    if status == :error, do: System.halt(1)
  end

  def run(operator_options) do
    case Config.fetch() do
      {:ok, %{profile: :aws} = config} -> run(config, operator_options)
      _invalid -> {:error, %{status: :failed, reason: :configured_aws_storage_required}}
    end
  end

  defp run(config, operator_options) do
    report = %{target: target(config), checked_at: DateTime.to_iso8601(DateTime.utc_now())}

    with {:ok, operator} <- operator_sdk(config, operator_options),
         {:ok, snapshot} <- inspect_bucket(config, operator),
         {:ok, controls} <-
           validate(snapshot, config, Application.fetch_env!(:quick_train, :assets)) do
      qualify_objects(config, operator, Map.put(report, :bucket_controls, controls))
    else
      {:error, reason} -> {:error, Map.merge(report, %{status: :failed, reason: reason})}
    end
  end

  def target(config) do
    %{
      endpoint: URI.to_string(config.endpoint),
      bucket: config.bucket,
      region: config.sdk.region,
      application_identity_sha256: digest(config.sdk.access_key_id)
    }
  end

  def operator_sdk(config, options) do
    access = options[:access_key_id]
    secret = options[:secret_access_key]
    token = options[:security_token]

    if nonempty?(access) and nonempty?(secret) and access != config.sdk.access_key_id and
         (is_nil(token) or nonempty?(token)) do
      sdk =
        config.sdk
        |> Map.delete(:security_token)
        |> Map.merge(%{access_key_id: access, secret_access_key: secret})

      {:ok, if(token, do: Map.put(sdk, :security_token, token), else: sdk)}
    else
      {:error, :operator_credentials_required}
    end
  end

  def inspect_bucket(config, operator) do
    bucket = config.bucket

    operations = [
      versioning: SDK.get_bucket_versioning(bucket),
      ownership: get_configuration(bucket, "ownershipControls"),
      public_access: get_configuration(bucket, "publicAccessBlock"),
      lifecycle: SDK.get_bucket_lifecycle(bucket),
      object_lock: get_configuration(bucket, "object-lock"),
      replication: SDK.get_bucket_replication(bucket),
      location: SDK.get_bucket_location(bucket)
    ]

    Enum.reduce_while(operations, {:ok, %{}}, fn {name, operation}, {:ok, documents} ->
      case inspect_document(name, operation, operator) do
        {:ok, body} -> {:cont, {:ok, Map.put(documents, name, body)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, documents} -> {:ok, %{target: target(config), documents: documents}}
      error -> error
    end
  end

  # These controls do not have operation constructors in ExAws.S3.
  defp get_configuration(bucket, resource),
    do: %ExAws.Operation.S3{http_method: :get, bucket: bucket, resource: resource}

  defp inspect_document(name, operation, operator) do
    case control(operation, operator) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, %{body: body}}} ->
        if absent_configuration?(name, body),
          do: {:ok, :absent},
          else: {:error, :bucket_inspection_failed}

      _failure ->
        {:error, :bucket_inspection_failed}
    end
  end

  def validate(snapshot, config, assets) do
    with true <- snapshot.target == target(config),
         documents <- Map.new(snapshot.documents, fn {name, body} -> {name, parse(body)} end),
         :ok <- validate_controls(documents, config),
         {:ok, lifecycle} <- validate_lifecycle(documents.lifecycle, safety_window(assets)) do
      {:ok,
       Map.merge(lifecycle, %{
         versioning: :enabled,
         ownership: :bucket_owner_enforced,
         public_access: :blocked
       })}
    else
      false -> {:error, :qualification_target_mismatch}
      {:error, _reason} = error -> error
    end
  rescue
    # reach:disable-next-line bare_rescue -- Provider configuration never appears in failures.
    _exception -> {:error, :invalid_bucket_configuration}
  catch
    _kind, _reason -> {:error, :invalid_bucket_configuration}
  end

  defp validate_controls(documents, config) do
    cond do
      bucket_region(documents.location) != config.sdk.region ->
        {:error, :qualification_target_mismatch}

      xpath(documents.versioning, ~x"/VersioningConfiguration/Status/text()"s) != "Enabled" ->
        {:error, :versioning_required}

      xpath(documents.versioning, ~x"/VersioningConfiguration/MfaDelete/text()"s) not in [
        "",
        "Disabled"
      ] ->
        {:error, :staging_retention_blocked}

      xpath(documents.ownership, ~x"/OwnershipControls/Rule/ObjectOwnership/text()"ls) != [
        "BucketOwnerEnforced"
      ] ->
        {:error, :bucket_owner_enforced_required}

      not public_access_blocked?(documents.public_access) ->
        {:error, :block_public_access_required}

      documents.object_lock != :absent or documents.replication != :absent ->
        {:error, :staging_retention_blocked}

      true ->
        :ok
    end
  end

  defp bucket_region(document) do
    case xpath(document, ~x"/LocationConstraint/text()"s) do
      "" -> "us-east-1"
      "EU" -> "eu-west-1"
      region -> region
    end
  end

  defp public_access_blocked?(document) do
    Enum.all?(
      ~w(BlockPublicAcls IgnorePublicAcls BlockPublicPolicy RestrictPublicBuckets),
      &(xpath(document, ~x"/PublicAccessBlockConfiguration/#{&1}/text()"s) == "true")
    )
  end

  defp safety_window(assets) do
    seconds =
      Enum.map(
        [:staging_lifetime_seconds, :upload_access_lifetime_seconds, :operation_claim_seconds],
        &Keyword.fetch!(assets, &1)
      )

    deadline = Keyword.fetch!(assets, :publication_deadline_ms)
    true = Enum.all?([deadline | seconds], &(is_integer(&1) and &1 > 0))
    Enum.sum(seconds) + div(deadline + 999, 1000)
  end

  defp validate_lifecycle(document, window) do
    rules = xpath(document, ~x"/LifecycleConfiguration/Rule"el)

    with true <- rules != [] and children(document) == List.duplicate("Rule", length(rules)),
         {:ok, summary} <- lifecycle_summary(rules, window),
         true <-
           summary.current_expiration_days != [] and summary.noncurrent_expiration_days != [] and
             summary.expired_delete_marker_cleanup do
      {:ok, summary}
    else
      _invalid -> {:error, :unsafe_staging_lifecycle}
    end
  end

  defp lifecycle_summary(rules, window) do
    initial = %{
      safety_window_seconds: window,
      current_expiration_days: [],
      noncurrent_expiration_days: [],
      expired_delete_marker_cleanup: false
    }

    Enum.reduce_while(rules, {:ok, initial}, fn rule, {:ok, summary} ->
      case lifecycle_rule(rule, window) do
        %{current: current, noncurrent: noncurrent, marker: marker} ->
          {:cont,
           {:ok,
            %{
              summary
              | current_expiration_days:
                  add_expiration_day(current, summary.current_expiration_days),
                noncurrent_expiration_days:
                  add_expiration_day(noncurrent, summary.noncurrent_expiration_days),
                expired_delete_marker_cleanup: marker or summary.expired_delete_marker_cleanup
            }}}

        :invalid ->
          {:halt, :invalid}
      end
    end)
  end

  defp add_expiration_day(nil, days), do: days
  defp add_expiration_day(day, days), do: [day | days]

  defp lifecycle_rule(rule, window) do
    expiration = xpath(rule, ~x"./Expiration"el)
    noncurrent = xpath(rule, ~x"./NoncurrentVersionExpiration"el)

    with true <-
           allowed_children?(
             rule,
             ~w(ID Status Filter Prefix Expiration NoncurrentVersionExpiration)
           ),
         true <- xpath(rule, ~x"./Status/text()"s) == "Enabled",
         true <- staging_filter?(rule),
         true <- expiration != [] or noncurrent != [],
         {:ok, expiration} <- expiration(expiration, window),
         {:ok, noncurrent} <- noncurrent_expiration(noncurrent, window) do
      Map.put(expiration, :noncurrent, noncurrent)
    else
      _invalid -> :invalid
    end
  end

  defp expiration([], _window), do: {:ok, %{current: nil, marker: false}}

  defp expiration([node], window) do
    days = xpath(node, ~x"./Days/text()"s)

    cond do
      children(node) == ["Days"] and safe_days?(days, window) ->
        {:ok, %{current: String.to_integer(days), marker: false}}

      children(node) == ["ExpiredObjectDeleteMarker"] and
          xpath(node, ~x"./ExpiredObjectDeleteMarker/text()"s) == "true" ->
        {:ok, %{current: nil, marker: true}}

      true ->
        :invalid
    end
  end

  defp expiration(_nodes, _window), do: :invalid
  defp noncurrent_expiration([], _window), do: {:ok, nil}

  defp noncurrent_expiration([node], window) do
    days = xpath(node, ~x"./NoncurrentDays/text()"s)

    if children(node) == ["NoncurrentDays"] and safe_days?(days, window),
      do: {:ok, String.to_integer(days)},
      else: :invalid
  end

  defp noncurrent_expiration(_nodes, _window), do: :invalid

  defp staging_filter?(rule) do
    case {xpath(rule, ~x"./Prefix"el), xpath(rule, ~x"./Filter"el)} do
      {[_prefix], []} ->
        xpath(rule, ~x"./Prefix/text()"s) == "assets/staging/"

      {[], [filter]} ->
        children(filter) == ["Prefix"] and
          xpath(filter, ~x"./Prefix/text()"s) == "assets/staging/"

      _invalid ->
        false
    end
  end

  defp safe_days?(value, window) do
    case Integer.parse(value) do
      {days, ""} -> days > 0 and days * 86_400 > window
      _invalid -> false
    end
  end

  def probe_plan do
    run_id = Ash.UUID.generate()
    bytes = "QuickTrain AWS qualification #{run_id}\n"
    staging = "assets/staging/#{run_id}/#{Ash.UUID.generate()}"
    checksum = "assets/staging/#{run_id}/#{Ash.UUID.generate()}"
    sealed = "assets/sealed/#{run_id}/#{digest(bytes)}"

    %{
      run_id: run_id,
      bytes: bytes,
      staging: staging,
      checksum: checksum,
      sealed: sealed,
      keys: [staging, checksum, sealed]
    }
  end

  defp qualify_objects(config, operator, report) do
    plan = probe_plan()
    report = Map.merge(report, %{run_id: plan.run_id, probe_keys: plan.keys})

    case inventory(config, operator, plan) do
      {:ok, []} ->
        result = probes(config, plan)
        cleanup = cleanup(config, operator, plan)
        report = Map.put(report, :cleanup, cleanup)

        case {result, cleanup.inventory_complete} do
          {:ok, true} ->
            {:ok,
             Map.merge(report, %{
               status: :qualified,
               probes: :passed,
               requalify_after:
                 "endpoint, bucket, region, application identity, or bucket-control changes"
             })}

          {{:error, reason}, _} ->
            {:error, Map.merge(report, %{status: :failed, reason: reason})}

          {:ok, false} ->
            {:error, Map.merge(report, %{status: :failed, reason: :probe_inventory_incomplete})}
        end

      _failure ->
        {:error,
         Map.merge(report, %{status: :failed, reason: :probe_namespace_not_empty_or_unreadable})}
    end
  end

  def inventory(config, operator, plan) do
    Enum.reduce_while(
      ["assets/staging/#{plan.run_id}/", "assets/sealed/#{plan.run_id}/"],
      {:ok, []},
      fn prefix, {:ok, versions} ->
        case inventory_prefix(config, operator, plan, prefix) do
          {:ok, entries} -> {:cont, {:ok, entries ++ versions}}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    )
  rescue
    # reach:disable-next-line bare_rescue -- Never expose provider content on inventory failures.
    _exception -> {:error, :probe_inventory_incomplete}
  catch
    :exit, _reason -> {:error, :probe_inventory_incomplete}
  end

  defp inventory_prefix(config, operator, plan, prefix) do
    operation = %{
      SDK.list_object_versions(config.bucket, prefix: prefix, max_keys: 1000)
      | parser: &Function.identity/1
    }

    case control(operation, operator) do
      {:ok, %{body: body}} ->
        document = parse(body)

        entries =
          document
          |> xpath(~x"/ListVersionsResult/Version | /ListVersionsResult/DeleteMarker"el,
            key: ~x"./Key/text()"s,
            version_id: ~x"./VersionId/text()"s
          )

        if xpath(document, ~x"/ListVersionsResult/Name/text()"s) == config.bucket and
             xpath(document, ~x"/ListVersionsResult/IsTruncated/text()"s) == "false" and
             Enum.all?(
               entries,
               &(&1.key in plan.keys and String.starts_with?(&1.key, prefix) and
                   &1.version_id not in ["", "null"])
             ) do
          {:ok, entries}
        else
          {:error, :probe_inventory_incomplete}
        end

      _failure ->
        {:error, :probe_inventory_incomplete}
    end
  end

  def cleanup(config, operator, plan) do
    case inventory(config, operator, plan) do
      {:ok, versions} ->
        remaining =
          Enum.reject(versions, fn object ->
            operation =
              SDK.delete_object(config.bucket, object.key, version_id: object.version_id)

            match?({:ok, %{status_code: 204}}, control(operation, operator))
          end)

        %{
          inventory_complete: true,
          deleted_versions: length(versions) - length(remaining),
          remaining_versions: remaining
        }

      {:error, _reason} ->
        %{
          inventory_complete: false,
          deleted_versions: 0,
          remaining_versions: [],
          inspect_keys: plan.keys
        }
    end
  end

  defp probes(config, plan) do
    budget =
      Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:publication_deadline_ms)

    expected = %{
      sha256: :crypto.hash(:sha256, plan.bytes),
      byte_size: byte_size(plan.bytes),
      media_type: "text/plain"
    }

    {:ok, post} =
      S3.writable_staging_access(
        plan.staging,
        byte_size(plan.bytes),
        DateTime.add(DateTime.utc_now(), 120)
      )

    check(
      not Enum.any?(Map.keys(post.form_fields), &(String.downcase(&1) == "acl")),
      :acl_free_upload_required
    )

    upload(config, post, plan.bytes) |> require_status([200, 201, 204], :descriptor_upload_failed)
    first = signed(config, :head, plan.staging)
    require_status(first, [200], :version_probe_failed)
    version = Req.Response.get_header(first, "x-amz-version-id") |> List.first()
    check(version not in [nil, "", "null"], :versioning_required)

    upload(config, post, plan.bytes <> "x")
    |> require_status([400, 403], :upload_cap_not_enforced)

    changed = %{post | form_fields: Map.put(post.form_fields, "Content-Type", "text/html")}
    upload(config, changed, plan.bytes) |> require_status([400, 403], :upload_fields_not_enforced)
    missing = %{post | form_fields: Map.delete(post.form_fields, "Content-Disposition")}
    upload(config, missing, plan.bytes) |> require_status([400, 403], :upload_fields_not_enforced)
    retargeted = %{post | form_fields: Map.put(post.form_fields, "key", plan.sealed)}

    upload(config, retargeted, plan.bytes)
    |> require_status([400, 403], :upload_destination_not_enforced)

    replacement = String.duplicate("x", byte_size(plan.bytes))
    upload(config, post, replacement) |> require_status([200, 201, 204], :version_probe_failed)
    old = signed(config, :get, plan.staging, query: [{"versionId", version}])
    require_status(old, [200], :version_probe_failed)
    check(old.body == plan.bytes, :version_probe_failed)
    :ok = S3.write_staging(plan.staging, [plan.bytes], byte_size(plan.bytes), budget)

    signed(config, :put, plan.checksum,
      body: "wrong",
      headers: [{"x-amz-checksum-sha256", Base.encode64(expected.sha256)}]
    )
    |> require_status([400], :checksum_not_enforced)

    signed(config, :head, plan.checksum) |> require_status([403, 404], :checksum_not_enforced)
    url = object_url(config, plan.staging)
    raw(config, :get, url) |> require_status([403], :unsigned_read_allowed)
    raw(config, :put, url, body: "unauthorized") |> require_status([403], :unsigned_write_allowed)

    {:ok, _publication} = S3.verify_and_publish(plan.staging, plan.sealed, expected, budget)
    {:ok, _existing} = S3.verify_and_publish(plan.staging, plan.sealed, expected, budget)
    {:ok, descriptor} = S3.sealed_read_access(plan.sealed, DateTime.add(DateTime.utc_now(), 120))
    downloaded = raw(config, :get, URI.to_string(descriptor.uri))
    require_status(downloaded, [200], :download_failed)
    check(downloaded.body == plan.bytes, :download_integrity_failed)

    for {name, value} <- [
          {"content-type", "application/octet-stream"},
          {"content-disposition", "attachment"},
          {"cache-control", "no-store"}
        ] do
      check(Req.Response.get_header(downloaded, name) == [value], :download_headers_invalid)
    end

    raw(config, :get, object_url(config, plan.sealed))
    |> require_status([403], :unsigned_read_allowed)

    tampered =
      descriptor.uri
      |> Map.update!(:query, &(&1 <> "&response-content-type=text/html"))
      |> URI.to_string()

    raw(config, :get, tampered) |> require_status([403], :download_signature_not_enforced)

    {:ok, expired} =
      SDK.presigned_url(config.sdk, :get, config.bucket, plan.sealed,
        expires_in: 1,
        start_datetime: DateTime.add(DateTime.utc_now(), -120),
        virtual_host: config.addressing == :virtual
      )

    raw(config, :get, expired) |> require_status([403], :download_expiry_not_enforced)

    signed(config, :put, plan.sealed, body: replacement, headers: [{"if-none-match", "*"}])
    |> require_status([409, 412], :conditional_publication_not_enforced)

    signed(config, :put, plan.sealed, body: replacement)
    |> require_status([403], :sealed_overwrite_allowed)

    sealed_version =
      signed(config, :head, plan.sealed)
      |> Req.Response.get_header("x-amz-version-id")
      |> List.first()

    check(sealed_version not in [nil, "", "null"], :versioning_required)
    signed(config, :delete, plan.sealed) |> require_status([403], :sealed_delete_allowed)

    signed(config, :delete, plan.sealed, query: [{"versionId", sealed_version}])
    |> require_status([403], :sealed_version_delete_allowed)

    {:ok, _facts} = S3.verify_sealed(plan.sealed, expected, budget)
    :ok
  rescue
    # reach:disable-next-line bare_rescue -- Qualification never reports signed capabilities or provider errors.
    _exception -> {:error, :application_probe_failed}
  catch
    {:qualification_error, reason} -> {:error, reason}
    _kind, _reason -> {:error, :application_probe_failed}
  end

  defp upload(config, descriptor, bytes) do
    raw(config, :post, URI.to_string(descriptor.uri),
      form_multipart:
        Map.to_list(descriptor.form_fields) ++
          [{descriptor.file_field, {bytes, filename: "qualification.bin"}}]
    )
  end

  defp signed(config, method, key, options \\ []) do
    body = Keyword.get(options, :body)

    headers =
      if method == :put do
        %{
          "content-type" => "application/octet-stream",
          "content-disposition" => "attachment",
          "cache-control" => "no-store",
          "content-length" => Integer.to_string(byte_size(body)),
          "x-amz-checksum-sha256" => Base.encode64(:crypto.hash(:sha256, body))
        }
        |> Map.merge(Map.new(Keyword.get(options, :headers, [])))
        |> Map.to_list()
      else
        Keyword.get(options, :headers, [])
      end

    {:ok, url} =
      SDK.presigned_url(config.sdk, method, config.bucket, key,
        expires_in: 60,
        virtual_host: config.addressing == :virtual,
        headers: headers,
        query_params: Keyword.get(options, :query, [])
      )

    raw(config, method, url, body: body, headers: headers)
  end

  defp object_url(config, key) do
    {:ok, signed} =
      SDK.presigned_url(config.sdk, :get, config.bucket, key,
        virtual_host: config.addressing == :virtual
      )

    signed |> URI.parse() |> Map.put(:query, nil) |> URI.to_string()
  end

  defp raw(config, method, url, options \\ []) do
    case Operation.run(@request_budget, fn _directory, _deadline ->
           HTTPClient.request(
             [method: method, url: url, tls_options: config.tls_options, timeout: @request_budget] ++
               options
           )
         end) do
      {:ok, response} -> response
      _failure -> throw({:qualification_error, :application_request_failed})
    end
  end

  defp control(operation, sdk) do
    sdk = Map.update!(sdk, :http_opts, &Keyword.put(&1, :timeout, @request_budget))

    Operation.run(@request_budget, fn _directory, _deadline ->
      ExAws.Operation.perform(operation, sdk)
    end)
  end

  defp require_status(response, statuses, reason),
    do: check(response.status in statuses, reason)

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: throw({:qualification_error, reason})

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp absent_configuration?(name, body) do
    code = Map.get(@absent_codes, name)
    is_binary(code) and xpath(parse(body), ~x"/Error/Code/text()"s) == code
  rescue
    # reach:disable-next-line bare_rescue -- Treat unreadable provider errors as inspection failure.
    _exception -> false
  catch
    :exit, _reason -> false
  end

  defp parse(:absent), do: :absent

  defp parse(body) when is_binary(body) and byte_size(body) <= 65_536,
    do: SweetXml.parse(body, dtd: :none, quiet: true)

  defp children(node), do: Enum.map(xpath(node, ~x"./*"el), &xpath(&1, ~x"name(.)"s))

  defp allowed_children?(node, allowed) do
    names = children(node)
    length(names) == length(Enum.uniq(names)) and Enum.all?(names, &(&1 in allowed))
  end
end
