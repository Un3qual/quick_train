defmodule QuickTrain.Integrations.SecretStore do
  @moduledoc "Secret-store boundary; persisted credentials contain references, never secret values."

  @callback fetch(secret_reference :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
