defmodule QuickTrain.AuthenticationErrorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias QuickTrain.Authentication.Error

  test "classifies only structured authentication failures" do
    structured = Error.exception(operation: :begin, category: :rate_limited)

    capture_log(fn ->
      assert {:error, %Error{category: :rate_limited}} =
               Error.wrap(:begin, {:error, structured})

      assert {:error, %Error{category: :internal_error}} =
               Error.wrap(:begin, {:error, RuntimeError.exception("rate_limited")})
    end)
  end
end
