## 1. Authentication Tooling and Persistence

- [ ] 1.1 Select and exactly pin a stable GA Oban release, update `.mise.toml`, `mix.exs`, and `mix.lock` together, and run its supported generator for the jobs-table migration.
- [ ] 1.2 Refine the OIDC login-transaction Ash resource, snapshot, and clean-database migration for hashed proof material, trusted callbacks, one-way lifecycle, expiry, retention, identities, and indexes.
- [ ] 1.3 Refine ExternalIdentity and Session resources, snapshots, and clean-database migrations for immutable issuer/subject identity, active-state checks, global-account-only sessions, private required unique token hashes, bounded lifetime and retention, and indexed lookup. Remove the organization relationship and replace the legacy `Accounts.issue_session/2` API plus existing organization-scoped callers and tests with the internal bearer-issuance path.

## 2. OIDC Login and Session Issuance

- [ ] 2.1 Implement the OIDC begin action with server-generated state, nonce, S256 PKCE, separate client redemption proof, trusted callback selection, collision handling, safe output/log filtering, and standard global, network-source, and outstanding-state admission limits enforced before persistence or provider work.
- [ ] 2.2 Implement the atomic pending-to-exchanging claim that verifies the client proof before provider contact and never reopens a claimed transaction.
- [ ] 2.3 Implement verified provider exchange, issuer/subject-only identity resolution, active identity/user locking, atomic new-user-and-identity creation with concurrency-safe uniqueness handling, deterministic display names, and fail-closed conflicts.
- [ ] 2.4 Implement atomic bearer issuance with the consumed transition, returning the opaque token once while persisting only its unique SHA-256 hash and global-user session metadata.

## 3. API Actor and Administration Boundaries

- [ ] 3.1 Enforce trusted-proxy-aware HTTPS for production begin, exchange, and callback traffic; reject insecure callback configuration outside exact nonproduction loopback use and reject non-HTTPS production issuer or discovered provider endpoints before provider contact; implement indexed bearer resolution; and install the active global user as both the Absinthe and Ash actor without selecting organization scope.
- [ ] 3.2 Replace generated foundation exposure with an explicit GraphQL root-field allowlist for OIDC begin/exchange; exclude authentication persistence resources and credential or PII fields from introspection, remove health and broad account operations, keep `/healthz`, and restrict GraphiQL to development.
- [ ] 3.3 Add the responsibility-named operator-only first-manager Mix task using transactional Ash actions and the exact user, organization, membership, `manager` role, and assignment identities, including deterministic conflict and concurrent-idempotency handling without creating capability keys or grants.
- [ ] 3.4 Add the responsibility-named authentication-retention worker and fixed periodic Oban schedule with independently idempotent login-transaction and inactive-session cleanup plus overlap prevention.

## 4. Focused Verification

- [ ] 4.1 Add OIDC integration tests for unpredictable server material, trusted callbacks, initiating-client binding, provider validation, successful exchange, concurrent one-time claims, nonreusable failed claims, admission-limit rejection before persistence, untrusted forwarding-header resistance, production HTTPS, and insecure callback, issuer, discovery, and provider-endpoint rejection before outbound contact.
- [ ] 4.2 Add identity and session tests for immutable issuer/subject linking, concurrent atomic first-account creation without orphan users, no email linking, deterministic display-name fallback, inactive-state denial, conflict handling, raw-token absence, unique hashes, and indexed bearer lookup.
- [ ] 4.3 Add API authorization tests for actor propagation, absent or invalid credentials, active-organization checks, current membership and capability enforcement, cross-organization nondisclosure, root-field allowlisting, authentication-resource and credential-field introspection denial, `/healthz`, and development-only GraphiQL.
- [ ] 4.4 Add tests for the exact first-manager relationship graph, absence of implicit capability grants, conflict atomicity, and concurrent idempotency plus automatic login-state and inactive-session cleanup that preserves live credentials and avoids overlapping jobs.
- [ ] 4.5 Review generated AshPostgres and Oban migrations from a clean database, document the reset requirement and runtime OIDC configuration, run `mise run openspec.validate`, and finish with `mise run verify`.
