## Why

QuickTrain cannot define reusable forms or collect paid task responses until organizations can ingest, version, and safely expose the content being evaluated. This change adds the first product domain: normalized, organization-owned datasets and immutable media assets with enough schema structure to support future repeated and nested records without JSONB or a later data-model rewrite.

## What Changes

- Add immutable, SHA-256-addressed asset metadata and a provider-neutral storage boundary that atomically verifies and seals one pinned object version, rejects active or falsely declared content, separates writable upload staging from sealed read objects, and automatically expires abandoned staging content without unbounded historical rescans through a uniquely scheduled periodic cleanup path for imported images and future generated mask assets.
- Add organization-owned datasets with race-safe immutable schema versions, record types, typed field definitions, and stable dataset-item identities.
- Add immutable dataset-item revisions backed by normalized records, value occurrences, and typed scalar or asset values, with a shared canonical typed fingerprint encoding and relational constraints that bind every revision to the schema's designated root record type and every value to its record's exact type; no dataset content is stored in JSONB columns.
- Add import batches with atomic batch and row idempotency, complete pre-validation request fingerprints, relationally staged normalized records, stable keyless-item targeting, source provenance, retry-safe append/finalization sealing, serialized persisted counters with read-time lease-aware lifecycle derivation, claim-time lease recovery, bounded cleanup of abandoned open batches, and stable customer external keys.
- Complete the OIDC-to-bearer-session handshake with server-generated state, PKCE, and separate client-bound redemption proof, server-pinned callback URIs, deterministic display-name fallback for verified-email-only users, fail-closed issuer/subject account linking that rejects disabled identities or users, explicit operator-reviewed legacy user/identity migration, revocation of organization-scoped credentials before sessions become global account authenticators, periodically enforced bounded login-state retention, and indexed one-way bearer-token resolution, then add deliberate GraphQL actions for dataset/schema creation, programmatic batch ingestion, asset registration/finalization, and organization-scoped reads.
- Keep authorization fail-closed: managers require an active organization, active organization membership, and explicit dataset capabilities; no dataset content is publicly browsable. Provide an operator-only bootstrap path for the first organization manager instead of exposing unauthenticated organization mutations.
- Preserve a forward-compatible record envelope: the first release accepts flat typed records, while ordinals and record types leave repeated and nested record values additive later.

Explicit non-goals for this change:

- Form definitions, project bindings, task selection, worker responses, reviews, exports, finance, payouts, and reputation. Those are separate approved follow-up changes.
- Customer-specific PostgreSQL tables, JSONB-backed item payloads, or arbitrary EAV trees.
- Implementing nested record values in the first release, despite reserving a clean extension boundary for them.
- External form imports, advanced annotation values, payment-provider integration, or frontend work.
- Selecting a production object-storage vendor; this change defines the asset contract and configurable storage adapter boundary.

This intentionally moves QuickTrain beyond a reusable backend template by adding its first product-specific content domain while retaining the existing account, organization, authorization, enterprise identity, and GraphQL foundations.

## Capabilities

### New Capabilities

- `api-authentication`: One-time OIDC exchange, opaque bearer-session issuance and resolution, bounded login-state retention, and a fail-closed GraphQL authentication boundary.
- `assets`: Immutable, content-addressed, organization-scoped asset registration, storage lifecycle, metadata, and authorized access.
- `datasets`: Versioned normalized dataset schemas, stable items, immutable item revisions, record envelopes, typed field values, and organization-scoped querying.
- `dataset-imports`: Idempotent, provenance-preserving programmatic import batches that create or revise dataset items from normalized typed input.

### Modified Capabilities

None.

## Impact

- Hardens the existing Accounts session, external-identity, and OIDC login-transaction resources, migrations, configuration, and API pipeline with cryptographically generated state, PKCE, and client-bound redemption proof, trusted callback selection, one-time exchange, immutable issuer/subject linking, active-identity and active-user enforcement, deterministic new-user display names, staged operator-reviewed migration of legacy local users and provider keys, null token hashes, and organization-scoped sessions, scheduled bounded retention, and required uniquely indexed bearer-token hashes.
- Adds new Ash domains and resources under `QuickTrain.Assets` and `QuickTrain.Datasets`, exported through the top-level boundary.
- Adds AshPostgres tables, constraints, indexes, migrations, and resource snapshots for authentication hardening, assets, dataset definitions, item revisions, records, typed values, and imports, plus the supported Oban jobs-table migration.
- Extends the GraphQL schema with the OIDC begin/exchange handshake plus authenticated, active-organization, capability-scoped dataset and asset actions; removes existing policy-disabled foundation fields from the public schema instead of exposing them to any bearer-authenticated account. Adds responsibility-named operator commands for legacy identity linking and first-manager bootstrap outside GraphQL.
- Adds a configurable asset-storage adapter plus a deterministic test implementation; no production vendor is selected here.
- Establishes typed value-family conventions that later Forms and Tasks changes can share in code without sharing persistence tables.
