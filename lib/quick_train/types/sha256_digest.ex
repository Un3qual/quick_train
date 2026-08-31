defmodule QuickTrain.Types.Sha256Digest do
  @moduledoc "A SHA-256 digest represented as lowercase hex and persisted as 32 bytes."

  use Ash.Type

  @encoded_size 64
  @raw_size 32

  @impl true
  def storage_type(_constraints), do: :binary

  def graphql_type(_constraints), do: :string

  def graphql_input_type(_constraints), do: :string

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    case decode(value) do
      {:ok, _digest} -> {:ok, value}
      :error -> {:error, message: "must be exactly 64 lowercase hexadecimal characters"}
    end
  end

  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(<<digest::binary-size(@raw_size)>>, _constraints) do
    {:ok, Base.encode16(digest, case: :lower)}
  end

  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints), do: decode(value)

  @impl true
  def dump_to_embedded(value, _constraints), do: cast_input(value, [])

  @impl true
  def cast_from_embedded(value, _constraints), do: cast_input(value, [])

  @impl true
  def matches_type?(value, _constraints) when is_binary(value) do
    match?({:ok, _digest}, decode(value))
  end

  def matches_type?(_value, _constraints), do: false

  defp decode(value) when byte_size(value) == @encoded_size do
    case Base.decode16(value, case: :lower) do
      {:ok, <<digest::binary-size(@raw_size)>>} -> {:ok, digest}
      :error -> :error
    end
  end

  defp decode(_value), do: :error
end
