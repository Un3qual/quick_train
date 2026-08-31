ash_fully_qualified_files = [
  "lib/quick_train/assets/asset/cleanup.ex",
  "lib/quick_train/datasets/dataset_import/cleanup.ex",
  "lib/quick_train/datasets/dataset_item_revision/actions/put.ex",
  "lib/quick_train/datasets/dataset_schema_version/actions/create_draft.ex",
  "lib/quick_train/enterprise_identity/directory_user/validations/identity_scope.ex"
]

checks =
  Enum.map(ExSlop.checks(), fn
    ExSlop.Check.Readability.UnaliasedModuleUse = check ->
      {check, files: %{excluded: ash_fully_qualified_files}}

    check ->
      {check, []}
  end)

%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: checks
      }
    }
  ]
}
