defmodule QuickTrain.Assets.Storage do
  @moduledoc "Provider-neutral storage contract for immutable organization assets."

  @type object_key :: String.t()
  @type deadline_ms :: pos_integer()

  @type access_descriptor :: %{
          required(:method) => :get | :put,
          required(:uri) => URI.t(),
          required(:headers) => [{String.t(), String.t()}],
          required(:expires_at) => DateTime.t(),
          optional(:max_bytes) => pos_integer()
        }

  @type expected_facts :: %{
          required(:sha256) => String.t(),
          required(:byte_size) => pos_integer(),
          required(:media_type) => String.t()
        }

  @type verified_facts :: %{
          required(:sha256) => String.t(),
          required(:byte_size) => pos_integer(),
          required(:media_type) => String.t(),
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer()
        }

  @type publish_result :: %{
          required(:sealed_key) => object_key(),
          required(:facts) => verified_facts(),
          required(:provider_in_flight_until) => DateTime.t()
        }

  @callback writable_staging_access(
              staging_key :: object_key(),
              byte_cap :: pos_integer(),
              expires_at :: DateTime.t()
            ) :: {:ok, access_descriptor()} | {:error, term()}

  @callback verify_and_publish(
              staging_key :: object_key(),
              sealed_key :: object_key(),
              expected :: expected_facts(),
              deadline_ms()
            ) :: {:ok, publish_result()} | {:error, term()}

  @callback verify_sealed(
              sealed_key :: object_key(),
              expected :: expected_facts(),
              deadline_ms()
            ) :: {:ok, verified_facts()} | {:error, term()}

  @callback retire_staging(
              staging_key :: object_key(),
              not_before :: DateTime.t(),
              deadline_ms()
            ) :: :ok | {:error, term()}

  @callback sealed_read_access(
              sealed_key :: object_key(),
              expires_at :: DateTime.t()
            ) :: {:ok, access_descriptor()} | {:error, term()}
end
