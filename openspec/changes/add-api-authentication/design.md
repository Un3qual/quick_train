## Context

See `proposal.md` for motivation and `specs/api-authentication/spec.md` for behavioral requirements.

QuickTrain already has Ash resources for users, external identities, sessions, and OIDC login transactions, plus provider helpers. The current GraphQL pipeline does not resolve a bearer session into an actor, sessions still carry template-era organization scope, and policy-disabled foundation operations remain in the public schema. This repository is a pre-product backend template with no production-data migration obligation, so the change can establish the intended model directly and require a clean local database.

## Goals / Non-Goals

**Goals:**

- Establish one reusable authentication boundary before any product domain is exposed.
- Keep one global `User` and make organization authority relational and action-specific.
- Make OIDC exchange one-time, bound to the initiating client, and fail closed on identity conflicts or inactive accounts.
- Keep bearer lookup one-way and indexed.
- Require encrypted production transport for OIDC and bearer-authenticated API requests, non-cacheable credential responses, and bound unauthenticated login admission before persistence or provider work.

**Non-Goals:**

- Preserve or transform legacy local users, provider keys, null-hash sessions, or organization-scoped sessions.
- Add passwords, refresh tokens, frontend login UI, a QuickTrain-hosted provider callback endpoint, provider selection, or configurable account-linking policies.
- Implement datasets, assets, or any other product domain.

## Decisions

### 1. Implement authentication as a prerequisite change

`add-api-authentication` is implemented and verified before product GraphQL operations are exposed. The dataset/assets change references this boundary instead of duplicating its resources, migrations, tests, or task list.

Alternative rejected: implementing authentication inside the first product change made unrelated review findings expand the dataset/import design and obscured which work was reusable foundation work.

### 2. Bind one-time exchange with server-owned proof material

Begin generates state, nonce, a standards-compliant PKCE verifier, and a distinct redemption secret from at least 256 bits of CSPRNG entropy each. It persists only a collision-checked state hash, nonce hash, verifier material needed for provider exchange, redemption-secret hash, the trusted client-callback configuration identity and exact URI, lifecycle state, expiry, and retention cutoff. The raw redemption secret is returned only to the initiating client and never enters provider parameters, callback material, logs, or persistence. Only S256 is supported.

The provider returns its authorization response to the exact trusted client-owned callback selected at begin. QuickTrain exposes no callback ingress and persists no provider authorization code before exchange. The initiating client hands the provider code and state to the unauthenticated GraphQL exchange together with its separate redemption secret; exchange reloads the exact callback URI persisted at begin and uses it for provider redemption. This keeps the application API GraphQL-only while making the callback-to-exchange handoff explicit.

Before creating login state or contacting a provider, a standard web-boundary limiter enforces configurable global and per-network-source request rates plus a cap on outstanding unexpired login transactions. Network source uses the direct peer unless forwarded addresses come from a configured trusted proxy, so caller-controlled forwarding headers cannot bypass the limit. The limiter rejects excess work without persisting another transaction. Production begin and exchange requests require HTTPS after resolving the scheme only through configured trusted proxies. Cleartext exchange requests are hard-rejected without redirecting; only a proof-free begin request may redirect before any login material is created or returned. The same boundary hard-rejects a cleartext request carrying a bearer credential before token lookup or GraphQL dispatch. Begin and exchange responses, and any other response carrying OIDC state, client proof, provider request material, or a raw bearer token, use `Cache-Control: no-store`. Production client-callback configuration, the configured issuer, and every discovered authorization, token, or key endpoint used by the flow must also use HTTPS and are rejected before provider contact otherwise. Exact loopback HTTP client callbacks are permitted only in development and test; provider endpoints receive no loopback exception.

Exchange hashes the presented redemption secret and compares it in constant time before provider contact. It atomically changes one unexpired transaction from `pending` to `exchanging`; only that claimant may redeem the provider response. The provider signature, issuer, audience, nonce, expiry, and exact persisted callback are then validated. Session creation and the final `consumed` transition commit together. A failure after the claim leaves the transaction unusable rather than reopening a replay window.

Alternative rejected: state and PKCE alone protect the provider flow but do not bind QuickTrain's API exchange to the client that initiated login when another client obtains the provider code and state. A QuickTrain-hosted callback was also rejected because it would add a non-GraphQL application endpoint and require another one-time code handoff or server-side authorization-code persistence despite the template having no frontend.

### 3. Link only by verified issuer and subject

The verified canonical issuer URI and subject are the immutable external identity. Exchange locks and rechecks the matched identity and global user before session issuance. Provider refresh can update nonidentity profile claims but cannot change lifecycle status or `user_id`.

A new identity requires a verified nonempty email. Display name uses the first nonblank trimmed `name` or `preferred_username`, falling back to the normalized email local part. Neither email nor display name participates in linking. Creation of the new global user and its issuer/subject identity is one transaction; concurrent resolution of the same identity converges on the winning graph and rolls back any losing user creation. Any email or identity conflict returns a nondisclosing `account_linking_conflict`.

The implementation does not inventory or migrate legacy users. Local databases created from the older template are reset rather than receiving a production migration framework.

Alternative rejected: email linking can merge unrelated accounts and makes provider claim changes an authority boundary.

### 4. Make bearer sessions global-account credentials only

Issuance returns a high-entropy opaque token once and stores its SHA-256 hash, user, expiry, revocation metadata, and authentication method. The hash has an Ash identity and database unique index for one-row lookup. The target Session schema has no organization authority; product actions derive the organization from their own resource or explicit relationship. Issuance caps expiry to the configured maximum session lifetime. Disabling a user immediately makes all of that user's sessions ineligible at authentication and at the shared organization-capability check without implicitly revoking or deleting the session rows. Automatic retention still deletes only expired or revoked sessions after the later applicable timestamp plus a fixed retention interval; separate authentication-event evidence is not deleted with the credential row.

The migration is written for a clean database and may remove template-era organization scope or strengthen non-null constraints without a legacy backfill. After the production transport check, authentication hashes the presented token, resolves an unexpired and unrevoked session, rechecks the global user is active, and installs that user as both Absinthe and Ash actor. The shared organization-capability path rechecks the same active-user invariant with active organization, membership, and capability facts so trusted internal use cannot authorize a disabled user. A later product capability may define a separate named relationship-bound authorization path, such as project eligibility followed by attempt ownership, but the bearer session alone never supplies that authority and this authentication change implements no such product path.

Alternative rejected: session-carried organization scope can silently widen or stale while membership and organization state change.

### 5. Keep public GraphQL deliberate

OIDC begin and exchange are state-changing generic Ash actions and are exposed as unauthenticated GraphQL mutations generated by AshGraphQL. Their structured results are typed Ash resources so AshGraphQL, rather than manual Absinthe objects and resolvers, owns the public payload types and action dispatch. The trusted network source is carried in Ash request context from the Phoenix boundary and is not a public GraphQL argument.

GraphQL requires a query root even though this prerequisite capability has no application reads. The only public query is therefore the scalar, read-only `apiVersion` action; it exposes no health, persistence, account, or product state. The only other public root fields are the two OIDC mutations. `/healthz` remains operational and outside GraphQL. GraphiQL is compiled or routed only in development. `Session`, `OidcLoginTransaction`, and `ExternalIdentity` resources and credential or PII attributes such as token hashes, provider subjects, proof hashes, verifier material, and raw provider claims are absent from public schema introspection. Broad policy-disabled foundation fields are removed from domain GraphQL exposure; internal Ash actions remain available only to trusted code and tests. Later product changes add only their deliberate authorized operations to this allowlist.

An operator-only Mix task accepts an exact global user UUID plus a normalized organization slug and name. It resolves these immutable authorization identities:

- the supplied active user UUID;
- the organization slug;
- the organization-and-user membership pair;
- role key `manager` in that organization;
- the organization, user, and role assignment.

The role name is `Manager`. The transaction creates missing facts and succeeds idempotently only when every existing fact belongs to the same active relationship graph. An inactive user, organization, or membership; a slug/name or role-name mismatch; a role owned by another organization; or an assignment mismatch is a conflict and leaves no partial changes. Concurrent identical invocations converge through the same identities and re-read the winning graph after uniqueness contention. This authentication change creates no capability keys or role grants; each product change owns its exact capabilities and any product-specific manager grants. The command uses responsibility-named Ash actions and is never reachable through GraphQL.

### 6. Use Oban only for bounded authentication retention

Select and exactly pin a stable GA Oban release and generate its supported jobs-table migration. A responsibility-named Accounts worker periodically deletes login transactions past their retention cutoff and inactive sessions past their retention boundary. Scheduler uniqueness avoids overlapping runs; each cleanup action remains independently idempotent and preserves unexpired transactions and active sessions.

QuickTrain does not recreate generic operations, event delivery, audit, or integration domains. Later product changes may add their own responsibility-specific workers using the same dependency.

## Risks / Trade-offs

- **[A claimed provider exchange cannot be retried]** -> Favor replay resistance; the client starts a new login after any failed claimed exchange.
- **[Clean-database migration discards local template data]** -> State the reset requirement before implementation and revisit this decision only if real production data exists before rollout.
- **[Bearer tokens are replayable until expiry or revocation]** -> Keep tokens high entropy, store only hashes, use short bounded lifetimes, reject every cleartext bearer request before token lookup, and keep raw-token responses non-cacheable.
- **[Unauthenticated begin can consume persistence]** -> Enforce global, network-source, and outstanding-state admission limits before transaction creation.
- **[First-manager setup is not self-service]** -> Keep the narrow operator command until an authenticated administration workflow exists.

## Migration Plan

1. Select the exact stable Oban release, update `.mise.toml`, `mix.exs`, and `mix.lock` together, and generate the supported jobs migration.
2. Refine OIDC login transactions for server-owned proof material, one-way claims, trusted callbacks, admission limits, and retention.
3. Refine external identity and session resources for issuer/subject-only linking, global-account sessions, indexed token hashes, and bounded inactive-session retention; generate Ash snapshots and migrations for a clean database.
4. Add production begin and exchange transport enforcement, trusted client-callback and provider-endpoint validation, cleartext bearer rejection before authentication, non-cacheable credential responses, and bearer resolution to the Phoenix/Absinthe pipeline, then expose the explicit public allowlist through typed AshGraphQL actions.
5. Add deterministic first-manager bootstrap and periodic authentication-state cleanup.
6. Verify the handshake, admission and transport controls, identity conflicts, inactive states, one-time concurrency, actor propagation, organization authorization, schema exposure, cleanup, and production routing.

Rollback before product data exists removes the new authentication migrations after revoking issued credentials. Once product domains rely on bearer sessions, rollback requires a deliberate replacement-authentication migration and is not an automatic schema downgrade.
