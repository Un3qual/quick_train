defmodule QuickTrain.Assets.S3QualificationTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage.S3.{Config, Qualification}

  defmodule FixtureHTTPClient do
    def request(method, url, _body, _headers, _options) do
      %{owner: owner, responses: responses} =
        Application.fetch_env!(:quick_train, :qualification_fixture)

      uri = URI.parse(url)
      resource = uri.query |> URI.decode_query() |> Map.keys() |> Enum.sort()
      send(owner, {:inspection_request, method, uri.host, uri.path, resource})

      case Map.fetch!(responses, {method, resource}) do
        function when is_function(function, 1) -> function.(uri)
        response -> response
      end
    end
  end

  setup do
    {:ok, config} =
      Config.new(
        profile: :aws,
        endpoint: "https://s3.us-west-2.amazonaws.com",
        region: "us-west-2",
        bucket: "runtime-bucket",
        addressing: :path,
        access_key_id: "application-access",
        secret_access_key: "application-secret",
        application_hosts: ["app.example.test"],
        cookie_domains: []
      )

    assets = Application.fetch_env!(:quick_train, :assets)
    on_exit(fn -> Application.delete_env(:quick_train, :qualification_fixture) end)
    {:ok, config: config, assets: assets, snapshot: snapshot(config)}
  end

  test "qualifies complete staging retention against the exact runtime target", context do
    assert {:ok, result} =
             Qualification.validate(context.snapshot, context.config, context.assets)

    assert result.safety_window_seconds == 4_650
    assert result.current_expiration_days == [1]
    assert result.noncurrent_expiration_days == [1]
    assert result.expired_delete_marker_cleanup
  end

  test "another bucket's passing inspection cannot qualify runtime storage", context do
    wrong = put_in(context.snapshot, [:target, :bucket], "disposable-bucket")

    assert {:error, :qualification_target_mismatch} =
             Qualification.validate(wrong, context.config, context.assets)
  end

  test "versioning, ownership and every public-access block must qualify", context do
    for {name, xml} <- [
          versioning:
            "<VersioningConfiguration><Status>Suspended</Status></VersioningConfiguration>",
          versioning:
            "<VersioningConfiguration><Status>Enabled</Status><MfaDelete>Enabled</MfaDelete></VersioningConfiguration>",
          ownership:
            "<OwnershipControls><Rule><ObjectOwnership>BucketOwnerPreferred</ObjectOwnership></Rule></OwnershipControls>",
          public_access:
            String.replace(context.snapshot.documents.public_access, "true", "false",
              global: false
            )
        ] do
      assert {:error, _reason} =
               Qualification.validate(
                 put_in(context.snapshot, [:documents, name], xml),
                 context.config,
                 context.assets
               )
    end
  end

  test "expiration ages must strictly exceed the full configured safety window", context do
    for field <- [
          :staging_lifetime_seconds,
          :upload_access_lifetime_seconds,
          :operation_claim_seconds
        ] do
      assets = Keyword.put(context.assets, field, 86_400)

      assert {:error, :unsafe_staging_lifecycle} =
               Qualification.validate(context.snapshot, context.config, assets)
    end

    assets = [
      staging_lifetime_seconds: 86_397,
      upload_access_lifetime_seconds: 1,
      operation_claim_seconds: 1,
      publication_deadline_ms: 1_000
    ]

    assert {:error, :unsafe_staging_lifecycle} =
             Qualification.validate(context.snapshot, context.config, assets)
  end

  test "missing, disabled, retained-count and incomplete expiration fail", context do
    lifecycle = context.snapshot.documents.lifecycle

    for xml <- [
          "<LifecycleConfiguration/>",
          String.replace(lifecycle, "Enabled", "Disabled"),
          String.replace(lifecycle, "<NoncurrentDays>1</NoncurrentDays>", ""),
          String.replace(
            lifecycle,
            "<NoncurrentDays>1</NoncurrentDays>",
            "<NoncurrentDays>1</NoncurrentDays><NewerNoncurrentVersions>1</NewerNoncurrentVersions>"
          ),
          String.replace(
            lifecycle,
            "<ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker>",
            "<ExpiredObjectDeleteMarker>false</ExpiredObjectDeleteMarker>"
          ),
          String.replace(lifecycle, "<Days>1</Days>", "<Days>0</Days>"),
          String.replace(lifecycle, "<Days>1</Days>", "<Date>2030-01-01T00:00:00Z</Date>")
        ] do
      assert {:error, :unsafe_staging_lifecycle} =
               Qualification.validate(
                 put_in(context.snapshot, [:documents, :lifecycle], xml),
                 context.config,
                 context.assets
               )
    end
  end

  test "broader, sealed, tagged and transition rules fail", context do
    lifecycle = context.snapshot.documents.lifecycle

    for xml <- [
          String.replace(lifecycle, "assets/staging/", "assets/"),
          String.replace(lifecycle, "assets/staging/", "assets/sealed/"),
          String.replace(
            lifecycle,
            "<Filter><Prefix>assets/staging/</Prefix></Filter>",
            "<Filter><And><Prefix>assets/staging/</Prefix><Tag><Key>retain</Key><Value>yes</Value></Tag></And></Filter>"
          ),
          String.replace(
            lifecycle,
            "</Rule>",
            "<Transition><Days>1</Days><StorageClass>GLACIER</StorageClass></Transition></Rule>",
            global: false
          ),
          String.replace(
            lifecycle,
            "</LifecycleConfiguration>",
            "<Rule><Status>Enabled</Status><Prefix>assets/sealed/</Prefix><Expiration><Days>10</Days></Expiration></Rule></LifecycleConfiguration>"
          )
        ] do
      assert {:error, :unsafe_staging_lifecycle} =
               Qualification.validate(
                 put_in(context.snapshot, [:documents, :lifecycle], xml),
                 context.config,
                 context.assets
               )
    end
  end

  test "Object Lock and replication block qualification", context do
    for {name, xml} <- [
          object_lock:
            "<ObjectLockConfiguration><ObjectLockEnabled>Enabled</ObjectLockEnabled></ObjectLockConfiguration>",
          replication:
            "<ReplicationConfiguration><Rule><Status>Enabled</Status><Prefix>assets/staging/</Prefix></Rule></ReplicationConfiguration>"
        ] do
      assert {:error, :staging_retention_blocked} =
               Qualification.validate(
                 put_in(context.snapshot, [:documents, name], xml),
                 context.config,
                 context.assets
               )
    end
  end

  test "malformed XML and entities produce only a sanitized failure", context do
    for xml <- [
          "<secret-credential",
          "<!DOCTYPE x [<!ENTITY leak SYSTEM 'file:///etc/passwd'>]><LifecycleConfiguration>&leak;</LifecycleConfiguration>"
        ] do
      assert {:error, :invalid_bucket_configuration} =
               Qualification.validate(
                 put_in(context.snapshot, [:documents, :lifecycle], xml),
                 context.config,
                 context.assets
               )
    end
  end

  test "operator credentials are explicit and separate from the application identity", context do
    for options <- [
          [],
          [access_key_id: "application-access", secret_access_key: "application-secret"],
          [access_key_id: :instance_role, secret_access_key: "secret"]
        ] do
      assert {:error, :operator_credentials_required} =
               Qualification.operator_sdk(context.config, options)
    end

    assert {:ok, sdk} =
             Qualification.operator_sdk(context.config,
               access_key_id: "operator-access",
               secret_access_key: "operator-secret"
             )

    assert sdk.access_key_id == "operator-access"
    assert sdk.host == context.config.sdk.host
    refute Map.has_key?(sdk, :security_token)
  end

  test "inspection uses only the runtime bucket and rejects inaccessible controls", context do
    responses =
      Enum.map(context.snapshot.documents, fn {name, xml} ->
        resource = Qualification.inspection_resource(name)

        response =
          if xml == :absent,
            do: absent(name),
            else: {:ok, %{status_code: 200, body: xml, headers: []}}

        {{:get, [resource]}, response}
      end)
      |> Map.new()

    Application.put_env(:quick_train, :qualification_fixture, %{
      owner: self(),
      responses: responses
    })

    sdk = Map.put(context.config.sdk, :http_client, FixtureHTTPClient)
    assert {:ok, snapshot} = Qualification.inspect_bucket(context.config, sdk)
    assert {:ok, _} = Qualification.validate(snapshot, context.config, context.assets)

    for _ <- 1..7 do
      assert_receive {:inspection_request, :get, "s3.us-west-2.amazonaws.com", "/runtime-bucket/",
                      [_resource]}
    end

    denied =
      Map.put(
        responses,
        {:get, ["lifecycle"]},
        {:ok, %{status_code: 403, body: "secret-provider-message", headers: []}}
      )

    Application.put_env(:quick_train, :qualification_fixture, %{owner: self(), responses: denied})
    assert {:error, :bucket_inspection_failed} = Qualification.inspect_bucket(context.config, sdk)
  end

  test "malformed missing-configuration responses fail inspection without leaking parser exits",
       context do
    responses =
      Map.new(context.snapshot.documents, fn {name, xml} ->
        response =
          if xml == :absent,
            do: absent(name),
            else: {:ok, %{status_code: 200, body: xml, headers: []}}

        {{:get, [Qualification.inspection_resource(name)]}, response}
      end)

    sdk = Map.put(context.config.sdk, :http_client, FixtureHTTPClient)

    for name <- [:object_lock, :replication] do
      malformed =
        Map.put(
          responses,
          {:get, [Qualification.inspection_resource(name)]},
          {:ok, %{status_code: 404, body: "<private-provider-detail", headers: []}}
        )

      Application.put_env(:quick_train, :qualification_fixture, %{
        owner: self(),
        responses: malformed
      })

      assert {:error, :bucket_inspection_failed} =
               Qualification.inspect_bucket(context.config, sdk)
    end
  end

  test "probe namespaces use normal key shapes and distinct UUIDs" do
    first = Qualification.probe_plan()
    second = Qualification.probe_plan()
    refute first.run_id == second.run_id
    assert String.starts_with?(first.staging, "assets/staging/#{first.run_id}/")

    assert first.sealed ==
             "assets/sealed/#{first.run_id}/" <>
               Base.encode16(:crypto.hash(:sha256, first.bytes), case: :lower)

    assert Enum.all?(first.keys, &String.contains?(&1, "/#{first.run_id}/"))
  end

  test "cleanup uses operator version deletes and reports denied cleanup precisely", context do
    plan = Qualification.probe_plan()
    object = %{key: plan.staging, version_id: "run-owned-version"}

    responses = %{
      {:get, ["max-keys", "prefix", "versions"]} => fn uri ->
        prefix = URI.decode_query(uri.query)["prefix"]
        objects = if String.starts_with?(object.key, prefix), do: [object], else: []
        versions_response(context.config.bucket, objects)
      end,
      {:delete, ["versionId"]} => {:ok, %{status_code: 403, body: "access denied", headers: []}}
    }

    Application.put_env(:quick_train, :qualification_fixture, %{
      owner: self(),
      responses: responses
    })

    sdk = Map.put(context.config.sdk, :http_client, FixtureHTTPClient)

    assert %{inventory_complete: true, deleted_versions: 0, remaining_versions: [^object]} =
             Qualification.cleanup(context.config, sdk, plan)

    expected_path = "/#{context.config.bucket}/#{plan.staging}"
    assert_receive {:inspection_request, :delete, _host, ^expected_path, ["versionId"]}
    refute_receive {:inspection_request, :delete, _host, _path, []}
  end

  test "cleanup refuses unknown objects and incomplete inventories", context do
    plan = Qualification.probe_plan()
    other = %{key: "assets/sealed/pre-existing/important", version_id: "existing-version"}
    sdk = Map.put(context.config.sdk, :http_client, FixtureHTTPClient)

    for response <- [
          versions_response(context.config.bucket, [other]),
          versions_response(context.config.bucket, [], true)
        ] do
      responses = %{{:get, ["max-keys", "prefix", "versions"]} => response}

      Application.put_env(:quick_train, :qualification_fixture, %{
        owner: self(),
        responses: responses
      })

      assert %{inventory_complete: false, deleted_versions: 0, inspect_keys: keys} =
               Qualification.cleanup(context.config, sdk, plan)

      assert keys == plan.keys
      refute_receive {:inspection_request, :delete, _host, _path, _params}
    end
  end

  test "malformed inventory preserves the cleanup key manifest without attempting deletion",
       context do
    plan = Qualification.probe_plan()
    sdk = Map.put(context.config.sdk, :http_client, FixtureHTTPClient)

    responses = %{
      {:get, ["max-keys", "prefix", "versions"]} =>
        {:ok, %{status_code: 200, body: "<private-provider-detail", headers: []}}
    }

    Application.put_env(:quick_train, :qualification_fixture, %{
      owner: self(),
      responses: responses
    })

    assert {:error, :probe_inventory_incomplete} =
             Qualification.inventory(context.config, sdk, plan)

    assert %{
             inventory_complete: false,
             deleted_versions: 0,
             remaining_versions: [],
             inspect_keys: keys
           } = Qualification.cleanup(context.config, sdk, plan)

    assert keys == plan.keys
    refute_receive {:inspection_request, :delete, _host, _path, _params}
  end

  defp versions_response(bucket, objects, truncated \\ false) do
    entries =
      Enum.map_join(objects, fn object ->
        "<Version><Key>#{object.key}</Key><VersionId>#{object.version_id}</VersionId></Version>"
      end)

    {:ok,
     %{
       status_code: 200,
       headers: [],
       body:
         "<ListVersionsResult><Name>#{bucket}</Name><IsTruncated>#{truncated}</IsTruncated>#{entries}</ListVersionsResult>"
     }}
  end

  defp snapshot(config) do
    %{
      target: Qualification.target(config),
      documents: %{
        versioning: "<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>",
        ownership:
          "<OwnershipControls><Rule><ObjectOwnership>BucketOwnerEnforced</ObjectOwnership></Rule></OwnershipControls>",
        public_access:
          "<PublicAccessBlockConfiguration><BlockPublicAcls>true</BlockPublicAcls><IgnorePublicAcls>true</IgnorePublicAcls><BlockPublicPolicy>true</BlockPublicPolicy><RestrictPublicBuckets>true</RestrictPublicBuckets></PublicAccessBlockConfiguration>",
        location: "<LocationConstraint>us-west-2</LocationConstraint>",
        object_lock: :absent,
        replication: :absent,
        lifecycle: """
        <LifecycleConfiguration>
          <Rule><ID>staging-expiration</ID><Status>Enabled</Status><Filter><Prefix>assets/staging/</Prefix></Filter>
            <Expiration><Days>1</Days></Expiration><NoncurrentVersionExpiration><NoncurrentDays>1</NoncurrentDays></NoncurrentVersionExpiration>
          </Rule>
          <Rule><ID>staging-markers</ID><Status>Enabled</Status><Filter><Prefix>assets/staging/</Prefix></Filter>
            <Expiration><ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker></Expiration>
          </Rule>
        </LifecycleConfiguration>
        """
      }
    }
  end

  defp absent(:object_lock),
    do:
      {:ok,
       %{
         status_code: 404,
         body: "<Error><Code>ObjectLockConfigurationNotFoundError</Code></Error>",
         headers: []
       }}

  defp absent(:replication),
    do:
      {:ok,
       %{
         status_code: 404,
         body: "<Error><Code>ReplicationConfigurationNotFoundError</Code></Error>",
         headers: []
       }}
end
