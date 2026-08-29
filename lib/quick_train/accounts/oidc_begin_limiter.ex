defmodule QuickTrain.Accounts.OidcBeginLimiter do
  @moduledoc false

  use Hammer, backend: :ets, algorithm: :sliding_window
end
