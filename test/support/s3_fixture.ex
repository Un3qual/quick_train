defmodule QuickTrain.S3Fixture do
  @moduledoc false

  alias QuickTrain.Assets.Storage.S3

  def configure do
    options = [
      profile: :local,
      endpoint: System.fetch_env!("QUICK_TRAIN_STORAGE_ENDPOINT"),
      bucket: System.fetch_env!("QUICK_TRAIN_STORAGE_BUCKET"),
      region: "us-east-1",
      access_key_id: System.fetch_env!("QUICK_TRAIN_STORAGE_ACCESS_KEY"),
      secret_access_key: System.fetch_env!("QUICK_TRAIN_STORAGE_SECRET_KEY"),
      addressing: :path,
      ca_file: System.fetch_env!("QUICK_TRAIN_STORAGE_CA_FILE"),
      application_hosts: ["localhost"],
      cookie_domains: []
    ]

    previous = Application.get_env(:quick_train, :s3_storage)
    Application.put_env(:quick_train, :s3_storage, options)

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:quick_train, :s3_storage, previous),
        else: Application.delete_env(:quick_train, :s3_storage)
    end)

    {:ok, storage} = S3.Config.fetch()
    :ok = S3.LocalSetup.run(storage, ["http://localhost:4005"])

    %{
      s3_config: storage,
      request:
        Req.new(
          retry: false,
          redirect: false,
          decode_body: false,
          connect_options: [transport_opts: storage.tls_options]
        )
    }
  end

  def use_adapter do
    previous = Application.fetch_env!(:quick_train, :assets)
    Application.put_env(:quick_train, :assets, Keyword.put(previous, :storage_adapter, S3))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:quick_train, :assets, previous) end)
  end
end
