defmodule QuickTrainWeb.GraphQL.Schema do
  @moduledoc "The explicit public GraphQL allowlist."

  use Absinthe.Schema, use_spec_compliant_int_scalar: true

  use AshGraphql,
    domains: [
      QuickTrain.Authentication,
      QuickTrain.Assets,
      QuickTrain.Datasets,
      QuickTrain.Forms
    ],
    define_relay_types?: true,
    relay_ids?: false

  query do
  end

  mutation do
  end

  @impl true
  def middleware(middleware, %{identifier: field}, %{identifier: object})
      when {object, field} in [
             {:asset, :sha256},
             {:asset_summary, :sha256},
             {:dataset_item_revision, :fingerprint}
           ] do
    middleware ++ [{{__MODULE__, :encode_digest}, []}]
  end

  def middleware(middleware, _field, _object), do: middleware

  def encode_digest(%{state: :resolved, value: <<digest::binary-size(32)>>} = resolution, _opts),
    do: %{resolution | value: Base.encode16(digest, case: :lower)}

  def encode_digest(resolution, _opts), do: resolution
end
