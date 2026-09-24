alias QuickTrain.Assets.Storage.S3.{Config, LocalSetup}

{:ok, _} = Application.ensure_all_started(:req)
{:ok, _} = Application.ensure_all_started(:ex_aws)

with {:ok, storage} <- Config.fetch(),
     {:ok, origins_json} <- System.fetch_env("QUICK_TRAIN_STORAGE_CORS_ORIGINS_JSON"),
     {:ok, origins} <- Jason.decode(origins_json),
     :ok <- LocalSetup.run(storage, origins) do
  Mix.shell().info(
    "Local storage ready at #{URI.to_string(storage.endpoint)}/#{storage.bucket} (versioning enabled)."
  )
else
  _failure ->
    Mix.raise(
      "Local storage bootstrap failed; check its loopback HTTPS endpoint, credentials, CA, " <>
        "localhost CORS origins and bucket controls."
    )
end
