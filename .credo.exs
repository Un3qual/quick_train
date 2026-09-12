Code.require_file("credo_checks/unaliased_module_use.ex", __DIR__)

checks =
  Enum.map(ExSlop.checks(), fn
    ExSlop.Check.Readability.UnaliasedModuleUse ->
      {QuickTrain.CredoChecks.UnaliasedModuleUse, []}

    check ->
      {check, []}
  end)

%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {Credo.Check.Design.AliasUsage,
           priority: :low, if_nested_deeper_than: 2, only: ~r/^QuickTrain\./}
          | checks
        ]
      }
    }
  ]
}
