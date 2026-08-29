## Why

QuickTrain cannot safely expose organization-owned product data until GraphQL can authenticate a global account and every product action can authorize its organization independently. Authentication is a reusable foundation and should be implemented and reviewed separately from datasets and assets.

## What Changes

- Complete a one-time OIDC begin/exchange handshake with server-generated state, nonce, S256 PKCE, a client-bound exchange proof, server-selected client-owned callbacks, HTTPS-only production provider endpoints, encrypted production authentication transport, non-cacheable credential responses, and bounded unauthenticated admission.
- Link accounts only by the verified issuer and subject, create each new user and external identity atomically, require active identities and users, and never link or reactivate an account by email.
- Issue high-entropy opaque bearer sessions, persist only indexed one-way token hashes, bound inactive-session retention, and make sessions authenticate only the global `User` rather than carrying organization authority.
- Resolve the bearer session into both the GraphQL and Ash actor without granting organization authority: organization-capability-authorized actions separately require an active organization, membership, and capability, while any later alternative authorization route must be explicitly owned by its product capability.
- Define an explicit public GraphQL allowlist that excludes authentication persistence resources and credential or PII fields, keep `/healthz` separate, restrict GraphiQL to development, and expose only OIDC begin/exchange without authentication.
- Add a deterministic operator-only first-manager bootstrap and bounded cleanup of expired OIDC login transactions and inactive sessions.

Explicit non-goals:

- Migrating production users, identities, or sessions. QuickTrain has no production-data compatibility contract; implementation may require a clean local database.
- Email-based account merging, configurable linking policies, password authentication, refresh tokens, frontend login UI, a QuickTrain-hosted provider callback endpoint, or organization authority embedded in sessions.
- Adding any product domain or selecting an external identity provider.

## Capabilities

### New Capabilities

- `api-authentication`: One-time OIDC exchange, opaque bearer-session issuance and resolution, bounded authentication-state retention, and a fail-closed GraphQL actor boundary.

### Modified Capabilities

None.

## Impact

- Refines the existing Accounts session, external-identity, and OIDC login-transaction resources, migrations, configuration, and API pipeline.
- Changes the reusable backend template from authentication-ready scaffolding to an authenticated GraphQL foundation suitable for later organization-owned product domains.
- Adds the durable-jobs dependency and supported jobs-table migration used by authentication-state cleanup and later responsibility-specific workers.
- Removes broad policy-disabled foundation fields from the public schema and adds responsibility-named operator bootstrap outside GraphQL.
