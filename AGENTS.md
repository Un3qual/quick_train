# QuickTrain agent instructions

- Use `mise` for the repository toolchain. Do not add Nix configuration.
- Keep the backend on stable/GA dependency releases and update `.mise.toml`, `mix.exs`, and the
  lockfile together.
- Prefer Ash and AshPostgres resources/actions over direct Ecto access.
- Preserve the single global `User` model. Organization membership is relational and optional;
  all sessions still require an account.
- Keep authorization fail-closed and explicitly scoped to an organization.
- GraphQL is the only application API. Do not add REST/JSON:API parity unless the product decision
  changes.
- Do not add a frontend, a principal abstraction, anonymous sessions, or generic revisions.
- Run `mise run verify` before merging changes.
