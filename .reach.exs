[
  layers: [
    web: ["QuickTrainWeb", "QuickTrainWeb.*"],
    runtime: ["QuickTrain.Application"],
    data: ["QuickTrain.Repo"],
    support: ["QuickTrain.ConnCase", "QuickTrain.DataCase", "Mix.Tasks.*"],
    domain: ["QuickTrain", "QuickTrain.*"]
  ],
  deps: [
    forbidden: [
      {:domain, :web, except: ["QuickTrain.Application"]}
    ]
  ],
  calls: [
    forbidden: [
      {"QuickTrain.*", ["QuickTrainWeb.*"], except: ["QuickTrain.Application"]},
      {"QuickTrain.*", ["Plug.*", "Phoenix.*", "Absinthe.*"],
       except: ["QuickTrain.Application", "QuickTrain.ConnCase"]}
    ]
  ],
  source: [
    forbidden_modules: [
      "QuickTrainWeb.JsonApi.*",
      "QuickTrainWeb.Rest.*"
    ],
    forbidden_files: [
      "lib/quick_train_web/json_api/**",
      "lib/quick_train_web/rest/**"
    ]
  ],
  clone_analysis: [
    provider: :ex_dna,
    min_mass: 80,
    min_similarity: 0.9,
    literal_mode: :abstract,
    normalize_pipes: true,
    excluded_macros: [:field, :query, :mutation, :resources, :attributes, :actions],
    max_clones: 1
  ],
  smells: [
    strict: true,
    fixed_shape_map: [min_keys: 3, min_occurrences: 5, evidence_limit: 10],
    behaviour_candidate: [
      min_modules: 3,
      min_callbacks: 3,
      module_display_limit: 8,
      callback_display_limit: 8
    ]
  ]
]
