defmodule QuickTrain.EnterpriseIdentity.Adapter do
  @moduledoc "Provider boundary for enterprise connection and directory synchronization APIs."

  @callback fetch_connection(external_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_directory_users(directory_external_id :: String.t(), cursor :: String.t() | nil) ::
              {:ok, %{users: [map()], next_cursor: String.t() | nil}} | {:error, term()}
  @callback list_directory_groups(directory_external_id :: String.t(), cursor :: String.t() | nil) ::
              {:ok, %{groups: [map()], next_cursor: String.t() | nil}} | {:error, term()}
end
