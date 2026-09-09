defmodule QuickTrain.Assets.Storage.Content do
  @moduledoc "Verifies opaque file bytes; the declared media type is untrusted metadata."

  def verify(bytes, %{sha256: hash, byte_size: size, media_type: media_type})
      when is_binary(bytes) and is_binary(hash) and byte_size(hash) == 32 and
             is_integer(size) and size > 0 and is_binary(media_type) do
    max_bytes = Application.fetch_env!(:quick_train, :assets) |> Keyword.fetch!(:max_bytes)

    if byte_size(bytes) == size and size <= max_bytes and :crypto.hash(:sha256, bytes) == hash do
      {:ok, %{sha256: hash, byte_size: size, media_type: media_type}}
    else
      {:error, :content_mismatch}
    end
  end

  def verify(_bytes, _expected), do: {:error, :content_mismatch}
end
