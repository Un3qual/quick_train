## 1. Authentication Tooling and Persistence

- [x] 1.1 Select and exactly pin a stable GA Oban release, update `.mise.toml`, `mix.exs`, and `mix.lock` together, and run its supported generator for the jobs-table migration.
- [x] 1.2 Refine the OIDC login-transaction Ash resource, snapshot, and clean-database migration for hashed proof material, trusted callbacks, one-way lifecycle, expiry, retention, identities, and indexes.
- [x] 1.3 Refine ExternalIdentity and Session resources, snapshots, and clean-database migrations for immutable issuer/subject identity, active-state checks, global-account-only sessions, private required unique token hashes, bounded lifetime and retention, and indexed lookup. Remove the organization relationship and replace the legacy `Accounts.issue_session/2` API plus existing organization-scoped callers and tests with the internal bearer-issuance path.

## 2. OIDC Login and Session Issuance

- [x] 2.1 Implement the OIDC begin action with server-generated state, nonce, S256 PKCE, separate client redemption proof, trusted client-owned callback selection, collision handling, safe output/log filtering, and standard global, network-source, and outstanding-state admission limits enforced before persistence or provider work.
- [x] 2.2 Implement client callback handoff through GraphQL exchange: accept the provider code and state with the separate client proof, expose no QuickTrain callback route, atomically claim the matching transaction from pending to exchanging only after proof verification and before provider contact, and never reopen a claimed transaction.
- [x] 2.3 Implement verified provider exchange, issuer/subject-only identity resolution, active identity/user locking, atomic new-user-and-identity creation with concurrency-safe uniqueness handling, deterministic display names, and fail-closed conflicts.
- [x] 2.4 Implement atomic bearer issuance with the consumed transition, returning the opaque token once while persisting only its unique SHA-256 hash and global-user session metadata.

## 3. API Actor and Administration Boundaries

- [x] 3.1 Enforce trusted-proxy-aware authentication transport at the Phoenix boundary: permit only proof-free begin redirects before login-material creation; hard-reject cleartext exchange and bearer traffic without redirect and before provider, token, or GraphQL work; reject insecure client-callback and provider endpoints; expose no QuickTrain provider-callback route; mark credential-bearing responses `Cache-Control: no-store`; resolve bearer sessions by indexed hash; and install the active global user as both the Absinthe and Ash actor without selecting organization scope.
- [x] 3.2 Replace generated foundation exposure with an explicit GraphQL root-field allowlist for OIDC begin/exchange; exclude authentication persistence resources and credential or PII fields from introspection, remove health and broad account operations, keep `/healthz`, and restrict GraphiQL to development.
- [x] 3.3 Add the responsibility-named operator-only first-manager Mix task using transactional Ash actions and the exact user, organization, membership, `manager` role, and assignment identities, including deterministic conflict and concurrent-idempotency handling without creating capability keys or grants.
- [x] 3.4 Add the responsibility-named authentication-retention worker and fixed periodic Oban schedule with independently idempotent login-transaction and inactive-session cleanup plus overlap prevention.
- [x] 3.5 Replace the manual Absinthe authentication types, fields, and resolvers with an `AshGraphql` schema backed by a responsibility-named behavior resource: expose typed OIDC begin/exchange generic actions as mutations, carry trusted network source through Ash request context, remove broad account domain declarations, and add only the scalar read-only `apiVersion` query required for the GraphQL query root.

## 4. Focused Verification

- [x] 4.1 Add OIDC integration tests for unpredictable server material, trusted client-owned callbacks, explicit provider-code-and-state handoff through GraphQL exchange, absence of a QuickTrain callback route, initiating-client binding, provider validation, successful exchange, concurrent one-time claims, nonreusable failed claims, admission-limit rejection before persistence, untrusted forwarding-header resistance, proof-free begin redirect safety, cleartext exchange hard rejection, no-store handling for login material and raw bearer issuance, production HTTPS, and insecure callback, issuer, discovery, and provider-endpoint rejection before outbound contact.
- [x] 4.2 Add identity and session tests for immutable issuer/subject linking, concurrent atomic first-account creation without orphan users, no email linking, deterministic display-name fallback, disabled-user session denial without implicit revocation, inactive-session cleanup preservation, conflict handling, raw-token absence, unique hashes, and indexed bearer lookup.
- [x] 4.3 Add API authorization tests for cleartext bearer rejection before token lookup or GraphQL dispatch, actor propagation, absent or invalid credentials, disabled-user denial in the shared capability path, active-organization checks, current membership and capability enforcement, denial when no product-owned alternative authorization contract exists, cross-organization nondisclosure, root-field allowlisting, authentication-resource and credential-field introspection denial, `/healthz`, and development-only GraphiQL.
- [x] 4.4 Add tests for the exact first-manager relationship graph, absence of implicit capability grants, conflict atomicity, and concurrent idempotency plus automatic login-state and inactive-session cleanup that preserves live credentials and avoids overlapping jobs.
- [x] 4.5 Review generated AshPostgres and Oban migrations from a clean database, document the reset requirement and runtime OIDC configuration, run `mise run openspec.validate`, and finish with `mise run verify`.

## 5. Review Remediation

- [x] 5.1 Upgrade Oidcc to the patched stable release, enforce advertised S256 support, redact GraphQL authentication inputs and results, and reuse only fully validated provider metadata until its advertised expiry.
- [x] 5.2 Replace exception-message parsing with structured constraint handling and prove independent concurrent first-login requests converge on one account graph.
- [x] 5.3 Move bearer eligibility into a responsibility-named Ash read action and cover unknown, expired, revoked, and retained-expired authentication state.
- [x] 5.4 Strengthen first-manager rollback coverage, make the clean-database authentication migration explicitly forward-only, and keep GraphQL assertions order-independent.
- [ ] 5.5 Run focused tests, `mise run openspec.validate`, and `mise run verify`, then commit and push the reviewed fixes.
