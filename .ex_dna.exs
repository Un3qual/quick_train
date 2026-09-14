%{
  paths: ["lib/"],
  min_mass: 80,
  min_occurrences: 2,
  min_similarity: 0.9,
  literal_mode: :abstract,
  normalize_pipes: true,
  excluded_macros: [:field, :query, :mutation, :resources, :attributes, :actions],
  # These normalized resources deliberately repeat DSL declarations for distinct
  # types and foreign keys. ExDNA's near-miss module comparison ignores the macro
  # exclusions above; extracting shared resource macros would hide those contracts.
  # Their validation, authorization, and mutation workflows remain analyzed.
  ignore: [
    "lib/quick_train/datasets/dataset_value/boolean.ex",
    "lib/quick_train/datasets/dataset_value/date_time.ex",
    "lib/quick_train/datasets/dataset_value/decimal.ex",
    "lib/quick_train/datasets/dataset_value/integer.ex",
    "lib/quick_train/datasets/dataset_value/text.ex",
    "lib/quick_train/tasks/attempt_input_presentation.ex",
    "lib/quick_train/tasks/task_input_answer.ex"
  ]
}
