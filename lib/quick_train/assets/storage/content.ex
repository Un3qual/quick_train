defmodule QuickTrain.Assets.Storage.Content do
  @moduledoc false

  # Plain text excludes tag-like markup, including custom elements and processing instructions.
  @active_pattern ~r/<[a-z!\/?][^>]*>/i
  @png_depths %{
    0 => [1, 2, 4, 8, 16],
    2 => [8, 16],
    3 => [1, 2, 4, 8],
    4 => [8, 16],
    6 => [8, 16]
  }
  @jpeg_start_of_frame [
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF
  ]

  def verify(bytes, expected) when is_binary(bytes) and is_map(expected) do
    config = Application.fetch_env!(:quick_train, :assets)

    with :ok <- bounded_size(bytes, expected, config),
         :ok <- matching_hash(bytes, expected),
         :ok <- reject_active_content(bytes),
         {:ok, media_type, dimensions} <- detect(bytes),
         :ok <- matching_media_type(media_type, expected),
         :ok <- bounded_dimensions(dimensions, config) do
      {:ok,
       expected
       |> Map.take([:sha256, :byte_size, :media_type])
       |> Map.merge(dimensions)}
    end
  end

  def verify(_bytes, _expected), do: {:error, :content_mismatch}

  defp bounded_size(bytes, %{byte_size: expected_size}, config)
       when is_integer(expected_size) and expected_size > 0 do
    size = byte_size(bytes)

    if size == expected_size and size <= Keyword.fetch!(config, :max_bytes) do
      :ok
    else
      {:error, :content_mismatch}
    end
  end

  defp bounded_size(_bytes, _expected, _config), do: {:error, :content_mismatch}

  defp matching_hash(bytes, %{sha256: expected_hash})
       when is_binary(expected_hash) and byte_size(expected_hash) == 32 do
    actual_hash = :crypto.hash(:sha256, bytes)
    if actual_hash == expected_hash, do: :ok, else: {:error, :content_mismatch}
  end

  defp matching_hash(_bytes, _expected), do: {:error, :content_mismatch}

  defp reject_active_content(<<"%PDF-", _rest::binary>>), do: {:error, :unsupported_media_type}

  defp reject_active_content(bytes) do
    if String.valid?(bytes) and Regex.match?(@active_pattern, bytes) do
      {:error, :active_content_rejected}
    else
      :ok
    end
  end

  defp detect(
         <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", width::32, height::32, depth, color,
           0, 0, interlace, crc::32, rest::binary>>
       )
       when interlace in [0, 1] do
    header = <<"IHDR", width::32, height::32, depth, color, 0, 0, interlace>>

    with true <- depth in Map.get(@png_depths, color, []),
         true <- :erlang.crc32(header) == crc,
         :ok <- png_chunks(rest, false) do
      {:ok, "image/png", %{width: width, height: height}}
    else
      _invalid -> {:error, :unsupported_media_type}
    end
  end

  defp detect(<<header::binary-size(6), width::little-16, height::little-16, _rest::binary>>)
       when header in ["GIF87a", "GIF89a"] do
    {:ok, "image/gif", %{width: width, height: height}}
  end

  defp detect(<<0xFF, 0xD8, rest::binary>>) do
    case jpeg_dimensions(rest) do
      {:ok, width, height} -> {:ok, "image/jpeg", %{width: width, height: height}}
      :error -> {:error, :unsupported_media_type}
    end
  end

  defp detect(bytes) do
    if String.valid?(bytes) do
      {:ok, "text/plain", %{}}
    else
      {:error, :unsupported_media_type}
    end
  end

  # Check framing and checksums without inflating attacker-controlled image data.
  defp png_chunks(
         <<length::32, type::binary-size(4), data::binary-size(length), crc::32, rest::binary>>,
         has_data?
       )
       when length < 2_147_483_648 do
    cond do
      :erlang.crc32([type, data]) != crc or type == "IHDR" ->
        :error

      type == "IEND" ->
        case {has_data?, data, rest} do
          {true, "", ""} -> :ok
          _invalid -> :error
        end

      true ->
        png_chunks(rest, has_data? or (type == "IDAT" and length > 0))
    end
  end

  defp png_chunks(_bytes, _has_data?), do: :error

  defp jpeg_dimensions(
         <<0xFF, marker, length::16, _precision::8, height::16, width::16, _components::8,
           _rest::binary>>
       )
       when marker in @jpeg_start_of_frame and length >= 8 and width > 0 and height > 0 do
    {:ok, width, height}
  end

  defp jpeg_dimensions(<<0xFF, 0xFF, rest::binary>>), do: jpeg_dimensions(<<0xFF, rest::binary>>)

  defp jpeg_dimensions(<<0xFF, marker, rest::binary>>)
       when marker in [0x01, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9] do
    jpeg_dimensions(rest)
  end

  defp jpeg_dimensions(<<0xFF, _marker, length::16, rest::binary>>) when length >= 2 do
    skip = length - 2

    if byte_size(rest) >= skip do
      <<_segment::binary-size(^skip), remaining::binary>> = rest
      jpeg_dimensions(remaining)
    else
      :error
    end
  end

  defp jpeg_dimensions(<<_byte, rest::binary>>), do: jpeg_dimensions(rest)
  defp jpeg_dimensions(_bytes), do: :error

  defp matching_media_type(media_type, %{media_type: media_type}), do: :ok
  defp matching_media_type(_actual, _expected), do: {:error, :content_mismatch}

  defp bounded_dimensions(%{width: width, height: height}, config) do
    max_width = Keyword.fetch!(config, :max_image_width)
    max_height = Keyword.fetch!(config, :max_image_height)
    max_pixels = Keyword.fetch!(config, :max_image_pixels)

    if width > 0 and height > 0 and width <= max_width and height <= max_height and
         width * height <= max_pixels do
      :ok
    else
      {:error, :image_bounds_exceeded}
    end
  end

  defp bounded_dimensions(%{}, _config), do: :ok
end
