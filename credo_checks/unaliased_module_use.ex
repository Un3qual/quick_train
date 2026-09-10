defmodule QuickTrain.CredoChecks.UnaliasedModuleUse do
  @moduledoc false

  use Credo.Check,
    id: "EXS3009",
    base_priority: :low,
    category: :readability,
    tags: [:ex_slop],
    param_defaults: [min_count: 3],
    explanations: ExSlop.Check.Readability.UnaliasedModuleUse.explanations()

  @impl true
  def run(source_file, params) do
    source_file
    |> ExSlop.Check.Readability.UnaliasedModuleUse.run(params)
    |> Enum.reject(&ash_module?/1)
    |> Enum.map(&%{&1 | check: __MODULE__})
  end

  defp ash_module?(%Credo.Issue{trigger: "Ash"}), do: true

  defp ash_module?(%Credo.Issue{trigger: "Ash." <> _module}), do: true

  defp ash_module?(_issue), do: false
end
