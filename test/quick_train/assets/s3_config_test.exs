defmodule QuickTrain.Assets.S3ConfigTest do
  use ExUnit.Case, async: false

  alias QuickTrain.Assets.Storage.S3.Config, as: StorageConfig

  @storage_env ~w(PROFILE ENDPOINT REGION BUCKET ACCESS_KEY SECRET_KEY SESSION_TOKEN ADDRESSING CA_FILE APPLICATION_HOSTS_JSON COOKIE_DOMAINS_JSON)

  setup %{tmp_dir: tmp_dir} do
    ca_file = Path.join(tmp_dir, "local-ca.pem")
    File.write!(ca_file, "TLS validates the certificate contents at connection time")

    config = [
      profile: :local,
      endpoint: "https://storage.example.test:9443",
      region: "us-east-1",
      bucket: "quick-train",
      access_key_id: "local-access",
      secret_access_key: "local-secret",
      addressing: :path,
      ca_file: ca_file,
      application_hosts: ["app.example.test"],
      cookie_domains: []
    ]

    original = Application.fetch_env(:quick_train, :s3_storage)
    on_exit(fn -> restore_app_env(:quick_train, :s3_storage, original) end)
    {:ok, config: config, ca_file: ca_file}
  end

  @moduletag :tmp_dir

  test "local configuration uses explicit credentials, endpoint, and trust", context do
    assert {:ok, config} = StorageConfig.new(context.config)
    assert config.profile == :local
    assert config.addressing == :path
    assert config.bucket == "quick-train"
    assert config.host == "storage.example.test"
    assert %URI{scheme: "https", host: "storage.example.test", port: 9443} = config.endpoint
    assert config.tls_options == [cacertfile: context.ca_file]
    assert config.sdk.access_key_id == "local-access"
    assert config.sdk.secret_access_key == "local-secret"
    refute Map.has_key?(config.sdk, :security_token)
    assert config.sdk.region == "us-east-1"
    assert config.sdk.scheme == "https://"
    assert config.sdk.host == "storage.example.test"
    assert config.sdk.port == 9443
    assert config.sdk.json_codec == Jason
    assert config.sdk.retries[:max_attempts] == 1
    assert config.sdk.debug_requests == false
  end

  test "missing storage configuration remains distinct from an invalid configuration", context do
    Application.delete_env(:quick_train, :s3_storage)
    assert {:error, :storage_not_configured} = StorageConfig.fetch()

    Application.put_env(:quick_train, :s3_storage, [])
    assert {:error, :invalid_storage_configuration} = StorageConfig.fetch()

    Application.put_env(:quick_train, :s3_storage, context.config)
    assert {:ok, %{profile: :local}} = StorageConfig.fetch()
  end

  test "configuration rejects missing fields and credential discovery", context do
    required =
      ~w(profile endpoint region bucket access_key_id secret_access_key addressing application_hosts cookie_domains)a

    for field <- required do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.delete(context.config, field))
    end

    for invalid <- [nil, %{}, [:local], [{"profile", :local}]] do
      assert {:error, :invalid_storage_configuration} = StorageConfig.new(invalid)
    end

    for value <- [nil, "", "  ", :instance_role, {:system, "AWS_ACCESS_KEY_ID"}] do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(context.config, :access_key_id, value))
    end
  end

  test "local HTTPS requires a readable CA file", context do
    for ca_file <- [nil, "", context.ca_file <> ".missing", Path.dirname(context.ca_file)] do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(context.config, :ca_file, ca_file))
    end
  end

  test "endpoints cannot weaken TLS or add URL components", context do
    for endpoint <- [
          "http://storage.example.test",
          "https://user:secret@storage.example.test",
          "https://storage.example.test/bucket",
          "https://storage.example.test?credential=secret",
          "https://storage.example.test#fragment",
          "https://storage.example.test:0",
          "https://storage.example.test:65536",
          "https://storage.example.test:invalid",
          "https://storage example.test",
          "https:///missing-host"
        ] do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(context.config, :endpoint, endpoint))
    end
  end

  test "host normalization rejects the same application host even on another port", context do
    config =
      Keyword.merge(context.config,
        endpoint: "https://STORAGE.EXAMPLE.TEST.:9443/",
        application_hosts: ["storage.example.test"]
      )

    assert {:error, :invalid_storage_configuration} = StorageConfig.new(config)

    config = Keyword.put(config, :application_hosts, ["APP.EXAMPLE.TEST."])

    assert {:ok, %{host: "storage.example.test", application_hosts: ["app.example.test"]}} =
             StorageConfig.new(config)
  end

  test "cookie domains reject both exact and descendant storage hosts", context do
    for domain <- ["storage.example.test", ".EXAMPLE.TEST.", "test"] do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(context.config, :cookie_domains, [domain]))
    end

    assert {:ok, %{cookie_domains: ["ample.test"]}} =
             StorageConfig.new(Keyword.put(context.config, :cookie_domains, [".AMPLE.TEST"]))
  end

  test "host and cookie declarations must be explicit lists of hostnames", context do
    for {field, values} <- [
          application_hosts: [[], nil, "app.example.test", ["https://app.example.test"], [""]],
          cookie_domains: [nil, ".example.test", ["https://example.test"], ["..example.test"]]
        ],
        value <- values do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(context.config, field, value))
    end

    assert {:ok, _config} = StorageConfig.new(Keyword.put(context.config, :cookie_domains, []))
  end

  test "virtual addressing validates the actual bucket hostname", context do
    config = Keyword.put(context.config, :addressing, :virtual)
    assert {:ok, result} = StorageConfig.new(config)
    assert result.host == "quick-train.storage.example.test"
    assert result.sdk.host == "storage.example.test"
    assert result.sdk.virtual_host == true
    assert {:ok, _result} = StorageConfig.new(Keyword.put(config, :bucket, "local.bucket"))

    assert {:error, :invalid_storage_configuration} =
             StorageConfig.new(
               Keyword.put(config, :application_hosts, ["QUICK-TRAIN.STORAGE.EXAMPLE.TEST."])
             )

    assert {:error, :invalid_storage_configuration} =
             StorageConfig.new(Keyword.put(config, :cookie_domains, [".storage.example.test"]))
  end

  test "AWS requires a matching regional endpoint and allows system trust", context do
    config =
      context.config
      |> Keyword.merge(
        profile: :aws,
        endpoint: "https://s3.us-west-2.amazonaws.com",
        region: "us-west-2"
      )
      |> Keyword.delete(:ca_file)

    assert {:ok, %{profile: :aws, tls_options: []}} = StorageConfig.new(config)

    dotted = Keyword.put(config, :bucket, "assets.example")
    assert {:ok, _result} = StorageConfig.new(dotted)

    assert {:error, :invalid_storage_configuration} =
             StorageConfig.new(Keyword.put(dotted, :addressing, :virtual))

    assert {:ok, _result} = StorageConfig.new(Keyword.put(config, :addressing, :virtual))

    for endpoint <- [
          "https://s3.amazonaws.com",
          "https://s3.us-east-1.amazonaws.com",
          "https://s3.us-west-2.amazonaws.com.attacker.test",
          "https://s3.us-west-2.amazonaws.com:9443",
          "https://storage.example.test"
        ] do
      assert {:error, :invalid_storage_configuration} =
               StorageConfig.new(Keyword.put(config, :endpoint, endpoint))
    end
  end

  test "ambient SDK settings cannot replace the declared credentials or safe behavior", context do
    original = Application.get_all_env(:ex_aws)

    on_exit(fn ->
      Enum.each(original, fn {key, value} -> Application.put_env(:ex_aws, key, value) end)
    end)

    keys = [:access_key_id, :secret_access_key, :security_token, :debug_requests, :s3]

    on_exit(fn ->
      Enum.each(keys -- Keyword.keys(original), &Application.delete_env(:ex_aws, &1))
    end)

    Application.put_env(:ex_aws, :access_key_id, :instance_role)
    Application.put_env(:ex_aws, :secret_access_key, :instance_role)
    Application.put_env(:ex_aws, :security_token, :instance_role)
    Application.put_env(:ex_aws, :debug_requests, true)

    Application.put_env(:ex_aws, :s3,
      host: "ambient.invalid",
      access_key_id: :instance_role,
      secret_access_key: :instance_role,
      security_token: :instance_role,
      refreshable: [:instance_role],
      retries: [max_attempts: 5]
    )

    assert {:ok, config} = StorageConfig.new(context.config)
    assert config.sdk.access_key_id == "local-access"
    assert config.sdk.secret_access_key == "local-secret"
    refute Map.has_key?(config.sdk, :security_token)
    assert config.sdk.host == "storage.example.test"
    assert config.sdk.debug_requests == false
    assert config.sdk.retries[:max_attempts] == 1

    assert {:ok, %{sdk: %{security_token: "explicit-session"}}} =
             StorageConfig.new(Keyword.put(context.config, :security_token, "explicit-session"))
  end

  test "runtime selects S3 only outside ordinary tests and rejects partial configuration",
       context do
    names = Enum.map(@storage_env, &("QUICK_TRAIN_STORAGE_" <> &1))
    original = Map.new(names, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(original, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    Enum.each(names, &System.delete_env/1)

    unconfigured = Config.Reader.read!("config/runtime.exs", env: :dev)
    refute unconfigured[:quick_train][:assets]
    refute unconfigured[:quick_train][:s3_storage]

    System.put_env(%{
      "QUICK_TRAIN_STORAGE_PROFILE" => "local",
      "QUICK_TRAIN_STORAGE_ENDPOINT" => "https://storage.example.test:9443",
      "QUICK_TRAIN_STORAGE_REGION" => "us-east-1",
      "QUICK_TRAIN_STORAGE_BUCKET" => "quick-train",
      "QUICK_TRAIN_STORAGE_ACCESS_KEY" => "local-access",
      "QUICK_TRAIN_STORAGE_SECRET_KEY" => "local-secret",
      "QUICK_TRAIN_STORAGE_ADDRESSING" => "path",
      "QUICK_TRAIN_STORAGE_CA_FILE" => context.ca_file,
      "QUICK_TRAIN_STORAGE_APPLICATION_HOSTS_JSON" => ~s(["app.example.test"]),
      "QUICK_TRAIN_STORAGE_COOKIE_DOMAINS_JSON" => "[]"
    })

    runtime = Config.Reader.read!("config/runtime.exs", env: :dev)
    assert runtime[:quick_train][:assets][:storage_adapter] == QuickTrain.Assets.Storage.S3
    assert runtime[:quick_train][:s3_storage][:cookie_domains] == []

    test_runtime = Config.Reader.read!("config/runtime.exs", env: :test)
    refute test_runtime[:quick_train][:assets]
    refute test_runtime[:quick_train][:s3_storage]

    System.delete_env("QUICK_TRAIN_STORAGE_COOKIE_DOMAINS_JSON")

    assert_raise RuntimeError, "invalid storage configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :dev)
    end

    System.put_env("QUICK_TRAIN_STORAGE_COOKIE_DOMAINS_JSON", "not-json-secret")

    assert_raise RuntimeError, "invalid storage configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :dev)
    end

    Enum.each(names, &System.delete_env/1)
    System.put_env("QUICK_TRAIN_STORAGE_COOKIE_DOMAINS_JSON", "null")

    assert_raise RuntimeError, "invalid storage configuration", fn ->
      Config.Reader.read!("config/runtime.exs", env: :dev)
    end
  end

  defp restore_app_env(app, key, :error), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
end
