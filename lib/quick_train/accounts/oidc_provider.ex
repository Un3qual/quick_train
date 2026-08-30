defmodule QuickTrain.Accounts.OidcProvider do
  @moduledoc false

  @callback authorization_url(map()) :: {:ok, String.t()} | {:error, term()}
  @callback exchange_code(String.t(), map()) :: {:ok, map()} | {:error, term()}
end
