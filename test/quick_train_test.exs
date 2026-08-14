defmodule QuickTrainTest do
  use ExUnit.Case
  doctest QuickTrain

  test "exposes the application boundary" do
    assert QuickTrain.module_info(:module) == QuickTrain
  end
end
