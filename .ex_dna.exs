%{
  paths: ["lib/"],
  min_mass: 80,
  min_occurrences: 2,
  min_similarity: 0.9,
  literal_mode: :abstract,
  normalize_pipes: true,
  excluded_macros: [:field, :query, :mutation, :resources, :attributes, :actions]
}
