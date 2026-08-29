## Why

QuickTrain cannot define reusable forms or collect paid task responses until organizations can ingest, version, and safely expose the content being evaluated. This change adds normalized, organization-owned datasets and immutable media assets with enough relational structure to support future repeated and nested records without JSONB or a later data-model replacement.

## What Changes

- Add immutable, SHA-256-addressed asset metadata and a provider-neutral storage boundary that verifies staging bytes before canonical publication, enforces bounded size and image dimensions, converges on one canonical sealed object, rejects active or falsely declared content, separates writable staging from sealed reads, and coordinates recoverable finalization with late-write-safe staging cleanup.
- Add organization-owned datasets with race-safe immutable schema versions, record types, typed field definitions, and stable dataset-item identities.
- Add immutable dataset-item revisions backed by normalized records, value occurrences, and typed scalar or asset values, with relational constraints that bind every revision to its schema's root record type and every value to its record's exact type.
- Add idempotent import batches and rows with bounded normalized relational staging, stable keyless-item targeting, source provenance, partial completion, open-batch expiry, row-derived progress, and atomically scheduled retry-safe row processing with terminal retry-exhaustion outcomes but no custom processing leases or persisted aggregate counters.
- Add deliberate GraphQL actions for dataset and schema lifecycle, programmatic import with paginated row-outcome inspection, asset registration and finalization, authorized asset access, and organization-scoped typed reads.
- Require the separate `add-api-authentication` change before exposing product GraphQL actions. Every product action remains fail-closed and requires an active organization, active membership, and explicit capability.
- Preserve the additive record envelope: the first release accepts flat single-cardinality typed records, while stable occurrences and record types leave repeated and nested values additive later.

Explicit non-goals:

- Authentication implementation; it is owned by the prerequisite `add-api-authentication` change.
- Form definitions, project bindings, task selection, worker responses, reviews, exports, finance, payouts, and reputation. Approved starting decisions remain in the documentation-only `record-future-product-architecture` change.
- Customer-specific PostgreSQL tables, JSONB-backed item payloads, arbitrary nested record input, external form imports, advanced task-answer annotations, payment-provider integration, or frontend work.
- Selecting a production object-storage vendor.

This intentionally moves QuickTrain beyond a reusable backend template by adding its first product content domain while keeping authentication and later product architecture in separately reviewable OpenSpec changes.

## Capabilities

### New Capabilities

- `assets`: Immutable, content-addressed, organization-scoped asset registration, storage lifecycle, metadata, and authorized access.
- `datasets`: Versioned normalized dataset schemas, stable items, immutable item revisions, record envelopes, typed field values, and organization-scoped querying.
- `dataset-imports`: Idempotent, provenance-preserving programmatic import batches that create or revise dataset items from structurally accepted normalized typed input.

### Modified Capabilities

None.

## Impact

- Adds new Ash domains and resources under `QuickTrain.Assets` and `QuickTrain.Datasets`, exported through the top-level boundary.
- Adds AshPostgres tables, constraints, indexes, migrations, and resource snapshots for assets, dataset definitions, item revisions, records, typed values, and imports.
- Uses the Oban dependency and jobs table established by `add-api-authentication` for responsibility-specific asset and import workers.
- Extends the authenticated GraphQL schema with active-organization, membership, and capability-scoped product actions.
- Adds a configurable asset-storage adapter plus deterministic development and test implementations; no production vendor is selected here.
- Establishes typed value-family conventions that later Forms and Tasks changes can share in code without sharing persistence tables.
