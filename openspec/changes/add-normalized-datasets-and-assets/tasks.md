## 1. Prerequisite and Product Domain Foundation

- [ ] 1.1 Confirm `add-api-authentication` is implemented and verified so product GraphQL operations have an authenticated Ash actor and the shared Oban dependency is available.
- [ ] 1.2 Use Igniter and the available Ash generators to add the `QuickTrain.Assets` and `QuickTrain.Datasets` domain skeletons, retaining only product-specific generated structure.
- [ ] 1.3 Add exact capability keys `assets.read`, `assets.manage`, `datasets.read`, `datasets.manage`, and `dataset_imports.manage`; add a product-owned idempotent action that grants them to a selected existing organization manager without a shared manifest or wildcard; and add shared fail-closed policy checks and denial coverage for active user, active organization, active membership, and explicit capability.
- [ ] 1.4 Export the product domains and storage behavior through the top-level `QuickTrain` boundary without adding generic service, operation, audit, or integration layers.

## 2. Immutable Asset Domain

- [ ] 2.1 Generate the Asset resource, snapshot, and migration, then refine organization ownership, lifecycle, canonical SHA-256, finite configurable byte and image bounds, size, media type, image dimensions, staging and canonical sealed keys, staging expiry, cleanup completion, bounded operation-claim facts, ready-only uniqueness, constraints, and indexes.
- [ ] 2.2 Define `QuickTrain.Assets.Storage` and deterministic development and test adapters for staging access that enforces the declared byte cap or fails closed, staging-byte verification before canonical-key conditional publication, a finite publication deadline and bounded provider in-flight window, late-write-safe staging retirement, and short-lived sealed reads without per-registration sealed copies.
- [ ] 2.3 Enforce encrypted approved destinations and credential-safe redirect handling in storage access descriptors without exposing persistent storage keys or credentials through GraphQL.
- [ ] 2.4 Implement authorized asset registration that returns writable staging access only when the adapter enforces the declared byte cap, with canonical ready-asset reuse only when hash, byte size, and media type all match.
- [ ] 2.5 Implement bounded, recoverable, atomically claimed idempotent finalization that pins or fences and verifies staging bytes before canonical publication, rechecks the live claim immediately before starting a deadline-bounded publication, reconciles and reverifies an already-published canonical object after claim takeover, checks claim identity on completion, enforces bounded reads and image metadata, rejects active formats, records sanitized failures, and performs the immutable ready transition without holding a database transaction across storage I/O.
- [ ] 2.6 Implement concurrent ready-content and sealed-object convergence plus canonical-asset-linked `duplicate_content` handling while preserving organization-scoped authorization and exact metadata agreement.
- [ ] 2.7 Implement the responsibility-named verification worker with idempotent enqueue and resource-identity-only job arguments.
- [ ] 2.8 Implement periodic staging cleanup over the expired-and-not-cleaned index using a bounded mutually exclusive claim with expired-claim replacement and eligibility recheck; after replacing a finalization claim, treat canonical absence as provisional until its bounded provider publication window ends and recheck it; reconcile any prior canonical publication before cleanup completion, retire the staging identity only after upload descriptors and bounded in-flight writes expire or further writes are fenced, and record cleanup completion only after deletion or absence confirmation without holding a database transaction across storage I/O or deleting sealed reads.
- [ ] 2.9 Expose only registration, finalization, authorized access, and scoped read operations through authenticated GraphQL.
- [ ] 2.10 Add focused adapter and resource tests for enforced upload caps and fail-closed unsupported adapters, finalization byte and decompression-bomb limits, mismatch rejection before canonical publication, immutable canonical sealing and reverification, overwrite races, active-format rejection, deduplication without sealed-copy leaks, metadata conflicts, secure access, and cross-organization denial.
- [ ] 2.11 Add focused worker tests for verification retry, finalization/cleanup serialization, abandoned-claim replacement and stale-worker fencing, post-publication claim-loss reconciliation, claim expiry during bounded canonical publication, late-upload recreation prevention, abandoned and duplicate staging cleanup, cleanup-marker retry, scan exclusion, overlap prevention, and sealed-object preservation.

## 3. Versioned Dataset Schemas

- [ ] 3.1 Generate Dataset, DatasetSchemaVersion, DatasetRecordType, and DatasetFieldDefinition resources with snapshots, migrations, organization ownership, relationships, identities, constraints, and indexes.
- [ ] 3.2 Implement draft-only record-type and field editing for text, integer, decimal, boolean, UTC date-time, and asset families with `single` cardinality and requiredness.
- [ ] 3.3 Make every schema child edit lock and recheck the parent version so no mutation can commit after publication.
- [ ] 3.4 Implement atomic schema publication with exactly one same-schema designated root type and immutable post-publication behavior.
- [ ] 3.5 Expose deliberate dataset and schema lifecycle actions plus scoped typed reads through GraphQL.
- [ ] 3.6 Add focused policy, lifecycle, validation, same-schema constraint, publication-race, and GraphQL tests.

## 4. Normalized Items, Revisions, and Typed Values

- [ ] 4.1 Generate DatasetItem, DatasetItemRevision, DatasetRecord, DatasetValue, and the six scalar or asset typed-value resources with snapshots and migrations.
- [ ] 4.2 Add composite same-dataset, same-schema, exact-record-type, designated-root-type, item, revision, field, and asset relationships with required identities, foreign keys, and indexes.
- [ ] 4.3 Add the generated deferred constraint trigger that enforces exactly one compatible typed child per value occurrence and cover the database boundary directly.
- [ ] 4.4 Implement transactional flat-record construction that resolves fields only within the exact root record type and enforces required or optional single-cardinality occurrence counts.
- [ ] 4.5 Implement the versioned revision fingerprint encoder with canonical typed bytes and schema-aware identity.
- [ ] 4.6 Implement atomic stable-item get-or-create and item-locked immutable revision creation with monotonic revision numbers and unchanged detection.
- [ ] 4.7 Implement paginated typed item and revision reads without generic update or delete mutations for immutable content.
- [ ] 4.8 Add focused tests for typed round trips, invalid child combinations, cross-boundary references, field cardinality, fingerprint equivalence and divergence, first-item races, revision ordering, unchanged detection, and historical immutability.

## 5. Simplified Programmatic Imports

- [ ] 5.1 Generate DatasetImport and DatasetImportRow resources with snapshots and migrations for `open` or `sealed` phase, expiry, idempotency identities, source provenance, pending or terminal row outcomes, candidate-record references, and progress-query indexes.
- [ ] 5.2 Implement atomic import open-or-return behavior over organization, dataset, idempotency key, immutable parameters, and a same-dataset published schema.
- [ ] 5.3 Define the one-row flat GraphQL input; select, test, and document safe default request, import-row, field-count, scalar-byte, and text-byte limits; and ensure oversized input, malformed scalar shapes, unsupported structures, and nesting fail before canonicalization or row acceptance.
- [ ] 5.4 Implement canonical fingerprints for structurally accepted rows, including the external-key presence marker and persisted value, plus atomic row-key and source-position retry handling and pre-persistence duplicate-external-key rejection.
- [ ] 5.5 Implement append-time schema validation that stores valid normalized candidates as pending rows and domain-invalid inputs as terminal failed provenance without opaque payloads or partial graphs.
- [ ] 5.6 Use the import-row UUID as the stable target item UUID for keyless valid rows without creating an item during append.
- [ ] 5.7 Implement import-locked finalization that atomically seals the accepted row set and inserts the complete unique bounded-retry row-job set, rolling back sealing on any scheduling failure and preserving safe concurrent and lost-response retries.
- [ ] 5.8 Implement unique bounded-retry row jobs with terminal-row checks, atomic item-revision/outcome commits, and an automatic sanitized terminal outcome when no retry remains, using the simplest supported Oban lifecycle mechanism without leases, fences, persisted row attempt counters, or a scheduled scanner. If the selected Oban release cannot guarantee that outcome, pause and update the design with evidence before adding reconciliation.
- [ ] 5.9 Implement automatic expired-open-import cleanup under the same import lock while preserving every sealed import and finalized provenance row.
- [ ] 5.10 Implement derived batch counts and lifecycle queries over indexed row outcomes without persisted aggregate counters or a separate processing state.
- [ ] 5.11 Add focused import tests for batch and row idempotency, structurally rejected input, domain-invalid provenance, equivalent fingerprints, duplicate external keys, keyless identity, partial completion, and schema or asset scope.
- [ ] 5.12 Add focused concurrency and worker tests for append/finalize and finalize/cleanup races, atomic row-job scheduling rollback, row failure before commit, retry after terminal commit, retry-exhaustion terminal outcomes, concurrent item revisions, derived progress, and cross-organization denial.

## 6. Integration and Verification

- [ ] 6.1 Review all generated AshPostgres snapshots and migrations together, including composite keys, typed-child enforcement, asset partial uniqueness, canonical hash constraints, import idempotency, expiry cleanup, row outcomes, and supporting indexes.
- [ ] 6.2 Exercise the complete authenticated workflow: create and publish a schema, register and seal an asset, import mixed valid and invalid rows, retry open and append requests, finalize and process rows, and query typed historical revisions under organization authorization.
- [ ] 6.3 Document required product capability bootstrap, production storage configuration, asset staging lifetime, import open lifetime, and responsibility-specific Oban schedules without selecting a storage provider.
- [ ] 6.4 Run `mise run openspec.validate`, format and compile the implementation, inspect relevant logs and focused tests, and finish with `mise run verify` from a clean migrated database.
