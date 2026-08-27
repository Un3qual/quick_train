## 1. Tooling and Product Authorization Foundation

- [ ] 1.1 Use Igniter and the available Ash generators to add the `QuickTrain.Assets` and `QuickTrain.Datasets` domain skeletons, retaining only the generated structure needed for these product domains.
- [ ] 1.2 Select and exactly pin a stable GA Oban release through the repository toolchain, updating `mix.exs`, `mix.lock`, and any required `.mise.toml` task or environment configuration together.
- [ ] 1.3 Add the product capability keys for asset read/management and dataset read/management/import, including deterministic bootstrap or seed behavior and tests for active, inactive, and cross-organization memberships.
- [ ] 1.4 Implement bearer-session resolution in the Phoenix API pipeline so GraphQL requests receive an active global `User` as both the Absinthe and Ash actor, with fail-closed handling for missing, invalid, expired, or inactive sessions.
- [ ] 1.5 Audit the GraphQL domain registrations touched by the actor pipeline and remove or isolate policy-disabled product reachability so `/healthz` and the authentication handshake remain the only intended unauthenticated surfaces.
- [ ] 1.6 Add focused GraphQL integration tests proving unauthenticated denial, active-session actor propagation, explicit capability enforcement, and cross-organization non-disclosure before exposing product actions.

## 2. Immutable Asset Domain

- [ ] 2.1 Generate the Asset resource, snapshot, and migration, then refine its organization ownership, lifecycle, SHA-256 hash, byte size, media type, image dimensions, internal storage key, identities, constraints, and indexes.
- [ ] 2.2 Define the narrow `QuickTrain.Assets.Storage` behavior and implement deterministic development and test adapters for upload registration, content verification, and short-lived read access without exposing persistent credentials or locations.
- [ ] 2.3 Implement policy-protected asset registration and access actions that derive organization scope relationally and return only provider-neutral access descriptors.
- [ ] 2.4 Implement asset finalization as an idempotent state transition that verifies hash, size, supported media type, and positive image dimensions, records sanitized failures, and prevents ready content identity from changing.
- [ ] 2.5 Implement the responsibility-named asset verification worker and transactional/idempotent enqueue path, with clear behavior when production storage is not configured.
- [ ] 2.6 Expose only the deliberate asset registration, finalization, authorized-access, and scoped-read operations through GraphQL.
- [ ] 2.7 Add focused resource, policy, storage-adapter, worker, and GraphQL tests for successful finalization, mismatches, immutability, adapter failure, and cross-organization access denial.

## 3. Versioned Dataset Schemas

- [ ] 3.1 Generate Dataset, DatasetSchemaVersion, DatasetRecordType, and DatasetFieldDefinition resources with snapshots and migrations, then refine their relationships, organization ownership, identities, constraints, and indexes.
- [ ] 3.2 Implement draft-only schema editing actions for the initial text, integer, decimal, boolean, UTC date-time, and asset value families, including unique field keys, requiredness, and declared cardinality.
- [ ] 3.3 Implement schema publication as a locked transaction that validates the complete schema graph, requires exactly one root record type for the first release, and makes the published version structurally immutable.
- [ ] 3.4 Implement creation of a new draft version from an existing published schema without mutating or re-pointing historical versions.
- [ ] 3.5 Add fail-closed Ash policies and deliberate GraphQL lifecycle/read actions for datasets and schema versions; do not expose generic mutations for published structures.
- [ ] 3.6 Add focused resource, policy, concurrency, and GraphQL tests for valid publication, duplicate or invalid fields, immutable published versions, version succession, and cross-organization denial.

## 4. Normalized Item Revisions and Typed Values

- [ ] 4.1 Generate DatasetItem, DatasetItemRevision, DatasetRecord, and DatasetValue resources with stable item identities, optional dataset-scoped external keys, schema pins, revision numbers, fingerprints, field occurrence ordinals, snapshots, migrations, constraints, and indexes.
- [ ] 4.2 Generate the six typed child resources for text, integer, decimal, boolean, UTC date-time, and asset values, then refine their one-to-one relationships and family-specific constraints.
- [ ] 4.3 Implement the narrow deferred PostgreSQL constraint trigger through an AshPostgres migration so every DatasetValue has exactly one typed child matching its field family at transaction commit.
- [ ] 4.4 Implement one private transactional record-construction workflow that resolves fields against the pinned published schema, validates required and unknown fields, rejects nested input explicitly, and creates no partial record graph.
- [ ] 4.5 Implement stable-item revision creation with an authoritative item-row lock, deterministic content fingerprinting, unchanged-content detection, and monotonic immutable revision assignment.
- [ ] 4.6 Validate asset-valued fields within the revision transaction so only compatible, ready assets owned by the same organization can be referenced without leaking unauthorized metadata.
- [ ] 4.7 Add paginated, typed GraphQL reads for items and revisions that return schema, record, field, ordinal, and concrete typed-value identity without exposing unrestricted value mutation.
- [ ] 4.8 Add focused tests for every value family, missing and unknown fields, type mismatches, unsupported nested values, typed-child commit constraints, historical immutability, unchanged fingerprints, concurrent revision ordering, and asset compatibility.

## 5. Idempotent Dataset Imports

- [ ] 5.1 Generate DatasetImport and DatasetImportRow resources with snapshots and migrations, then refine organization/dataset/schema/actor relationships, lifecycle state, source position, external key, fingerprints, terminal outcomes, result references, sanitized errors, identities, counters, and indexes.
- [ ] 5.2 Implement the policy-protected open-import action with organization/dataset/idempotency-key identity and request-fingerprint conflict detection.
- [ ] 5.3 Implement bounded append-row actions that validate normalized typed inputs without persisting opaque payload or JSONB staging columns and that assign stable row identities and source positions.
- [ ] 5.4 Implement row processing through the canonical item-revision workflow so new, changed, unchanged, and invalid rows each produce the specified atomic outcome and provenance.
- [ ] 5.5 Implement import finalization and derived batch lifecycle/counts, allowing valid rows to commit independently while interrupted unfinished rows remain safely retryable.
- [ ] 5.6 Implement the responsibility-named import worker with idempotent job insertion, terminal-row skipping, short item-lock transactions, and safe recovery after transient failures.
- [ ] 5.7 Expose only the deliberate open, append, finalize, inspect, and paginated outcome operations through authenticated GraphQL.
- [ ] 5.8 Add focused action, policy, worker, GraphQL, and independent-connection concurrency tests for identical retries, conflicting retries, partial failure, resume behavior, same-item races, and unauthorized asset or organization references.

## 6. Integration and Delivery Gates

- [ ] 6.1 Register the new domains, repositories, supervisors, workers, and GraphQL types through the existing top-level application boundaries without introducing a generic service or direct-Ecto product API.
- [ ] 6.2 Review generated migrations and Ash snapshots together, verifying foreign keys, uniqueness, deferred typed-value enforcement, lifecycle constraints, and indexes for organization scope, external keys, latest revisions, record fields, and import processing.
- [ ] 6.3 Exercise the complete GraphQL workflow in an integration test: authenticate, create and publish a schema, register/finalize an asset, import mixed rows, retry idempotently, and query typed historical revisions under correct organization authorization.
- [ ] 6.4 Run formatter, focused tests, migration checks, and `mise run openspec.validate`, resolving all warnings or artifact drift.
- [ ] 6.5 Run `mise run verify` from a clean migrated test database and record any operational configuration required for production storage and Oban without selecting a storage or payment provider.
