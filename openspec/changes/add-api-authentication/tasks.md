## 1. Authentication Tooling and Persistence

- [ ] 1.1 Select and exactly pin a stable GA Oban release, update `.mise.toml`, `mix.exs`, and `mix.lock` together, and run its supported generator for the jobs-table migration.
- [ ] 1.2 Refine the OIDC login-transaction Ash resource, snapshot, and clean-database migration for hashed proof material, trusted callbacks, one-way lifecycle, expiry, retention, identities, and indexes.
- [ ] 1.3 Refine ExternalIdentity and Session resources, snapshots, and clean-database migrations for immutable issuer/subject identity, active-state checks, global-account-only sessions, required unique token hashes, and indexed lookup.

## 2. OIDC Login and Session Issuance

- [ ] 2.1 Implement the OIDC begin action with server-generated state, nonce, S256 PKCE, separate client redemption proof, trusted callback selection, collision handling, and safe output/log filtering.
- [ ] 2.2 Implement the atomic pending-to-exchanging claim that verifies the client proof before provider contact and never reopens a claimed transaction.
- [ ] 2.3 Implement verified provider exchange, issuer/subject-only identity resolution, active identity/user locking, deterministic new-user display names, and fail-closed conflict handling.
- [ ] 2.4 Implement atomic bearer issuance with the consumed transition, returning the opaque token once while persisting only its unique SHA-256 hash and global-user session metadata.

## 3. API Actor and Administration Boundaries

- [ ] 3.1 Implement indexed bearer resolution in the Phoenix API pipeline and install the active global user as both the Absinthe and Ash actor without selecting organization scope.
- [ ] 3.2 Remove the GraphQL health field and policy-disabled foundation operations, keep `/healthz`, restrict GraphiQL to development, and allow only OIDC begin/exchange without an actor.
- [ ] 3.3 Add the responsibility-named operator-only first-manager Mix task using transactional Ash actions for organization, membership, role assignment, and initial grants.
- [ ] 3.4 Add the responsibility-named OIDC login-transaction cleanup worker and fixed periodic Oban schedule with independently idempotent cleanup and overlap prevention.

## 4. Focused Verification

- [ ] 4.1 Add OIDC integration tests for unpredictable server material, trusted callbacks, initiating-client binding, provider validation, successful exchange, concurrent one-time claims, and nonreusable failed claims.
- [ ] 4.2 Add identity and session tests for immutable issuer/subject linking, no email linking, deterministic display-name fallback, inactive-state denial, conflict handling, raw-token absence, unique hashes, and indexed bearer lookup.
- [ ] 4.3 Add API authorization tests for actor propagation, absent or invalid credentials, active-organization checks, current membership and capability enforcement, cross-organization nondisclosure, minimal GraphQL exposure, `/healthz`, and development-only GraphiQL.
- [ ] 4.4 Add tests for first-manager bootstrap atomicity and idempotency plus automatic login-state cleanup that preserves live transactions and avoids overlapping jobs.
- [ ] 4.5 Review generated AshPostgres and Oban migrations from a clean database, document the reset requirement and runtime OIDC configuration, run `mise run openspec.validate`, and finish with `mise run verify`.
