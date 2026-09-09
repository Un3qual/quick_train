> Current scope update (2026-09-09): bootstrap and maintenance work recorded as completed below was subsequently removed by explicit request. Section 14 supersedes those historical steps. Restoration is future work in `restore-operator-bootstrap-and-maintenance`, not an incomplete prerequisite for this change.

## 1. Prerequisite and Product Domain Foundation

- [x] 1.1 Confirm `add-api-authentication` is implemented and verified so product GraphQL operations have an authenticated Ash actor and the shared Oban dependency is available.
- [x] 1.2 Use Igniter and the available Ash generators to add the `QuickTrain.Assets` and `QuickTrain.Datasets` domain skeletons, retaining only product-specific generated structure.
- [x] 1.3 Add exact capability keys `assets.read`, `assets.manage`, `datasets.read`, `datasets.manage`, and `dataset_imports.manage`; add a product-owned idempotent action that grants them to a selected existing organization manager without a shared manifest or wildcard; and add shared fail-closed policy checks and denial coverage for active user, active organization, active membership, and explicit capability.
- [x] 1.4 Export the product domains and storage behavior through the top-level `QuickTrain` boundary without adding generic service, operation, audit, or integration layers.

## 2. Immutable Asset Domain

- [x] 2.1 Generate the Asset resource, snapshot, and migration, then refine organization ownership, lifecycle, canonical SHA-256 with lowercase hexadecimal boundary representation and native 32-byte database storage, finite configurable byte and image bounds, size, media type, image dimensions, staging and canonical sealed keys, staging expiry, cleanup completion, bounded operation-claim facts, ready-only uniqueness, constraints, and indexes.
- [x] 2.2 Define `QuickTrain.Assets.Storage` and one deterministic in-memory adapter shared by development and tests for staging access that enforces the declared byte cap or fails closed, staging-byte verification before canonical-key conditional publication, a finite publication deadline and bounded provider in-flight window, late-write-safe staging retirement, and short-lived sealed reads without per-registration sealed copies.
- [x] 2.3 Enforce encrypted approved destinations and credential-safe redirect handling in storage access descriptors without exposing persistent storage keys or credentials through GraphQL.
- [x] 2.4 Implement authorized asset registration that returns writable staging access only when the adapter enforces the declared byte cap, with canonical ready-asset reuse only when hash, byte size, and media type all match.
- [x] 2.5 Implement bounded, recoverable, atomically claimed idempotent finalization that pins or fences and verifies staging bytes before canonical publication, rechecks the live claim immediately before starting a deadline-bounded publication, reconciles and reverifies an already-published canonical object after claim takeover, checks claim identity on completion, enforces bounded reads and image metadata, rejects active formats, records sanitized failures, and performs the immutable ready transition without holding a database transaction across storage I/O.
- [x] 2.6 Implement concurrent ready-content and sealed-object convergence plus canonical-asset-linked `duplicate_content` handling while preserving organization-scoped authorization and exact metadata agreement.
- [x] 2.7 Implement the responsibility-named verification worker with idempotent enqueue and resource-identity-only job arguments.
- [x] 2.8 Implement periodic staging cleanup over the expired-and-not-cleaned index using a bounded mutually exclusive claim with expired-claim replacement and eligibility recheck; after replacing a finalization claim, treat canonical absence as provisional until its bounded provider publication window ends and recheck it; reconcile any prior canonical publication before cleanup completion, retire the staging identity only after upload descriptors and bounded in-flight writes expire or further writes are fenced, and record cleanup completion only after deletion or absence confirmation without holding a database transaction across storage I/O or deleting sealed reads.
- [x] 2.9 Expose only registration, finalization, authorized access, scoped read operations, and the typed canonical-asset relationship through authenticated GraphQL.
- [x] 2.10 Add focused adapter and resource tests for enforced upload caps and fail-closed unsupported adapters, finalization byte and decompression-bomb limits, mismatch rejection before canonical publication, immutable canonical sealing and reverification, overwrite races, active-format rejection, deduplication without sealed-copy leaks, metadata conflicts, secure access, and cross-organization denial.
- [x] 2.11 Add focused worker tests for verification retry, finalization/cleanup serialization, abandoned-claim replacement and stale-worker fencing, post-publication claim-loss reconciliation, claim expiry during bounded canonical publication, late-upload recreation prevention, abandoned and duplicate staging cleanup, cleanup-marker retry, scan exclusion, overlap prevention, and sealed-object preservation.

## 3. Versioned Dataset Schemas

- [x] 3.1 Generate Dataset, DatasetSchemaVersion, DatasetRecordType, and DatasetFieldDefinition resources with snapshots, migrations, organization ownership, relationships, identities, constraints, and indexes.
- [x] 3.2 Implement draft-only record-type and field editing for text, integer, decimal, boolean, UTC date-time, and asset families with `single` cardinality and requiredness.
- [x] 3.3 Make every schema child edit lock and recheck the parent version so no mutation can commit after publication.
- [x] 3.4 Implement atomic schema publication with exactly one same-schema designated root type and immutable post-publication behavior.
- [x] 3.5 Expose deliberate dataset and schema lifecycle actions, typed singular relationships, and scoped to-many reads through keyset-paginated Relay connections in GraphQL.
- [x] 3.6 Add focused policy, lifecycle, validation, same-schema constraint, publication-race, and GraphQL tests.

## 4. Normalized Items, Revisions, and Typed Values

- [x] 4.1 Generate DatasetItem, DatasetItemRevision, DatasetRecord, DatasetValue, and the six scalar or asset typed-value resources with snapshots and migrations.
- [x] 4.2 Add composite same-dataset, same-schema, exact-record-type, designated-root-type, item, revision, field, and asset relationships with required identities, foreign keys, and indexes.
- [x] 4.3 Add the generated deferred constraint trigger that enforces exactly one compatible typed child per value occurrence and cover the database boundary directly.
- [x] 4.4 Implement transactional flat-record construction that resolves fields only within the exact root record type and enforces required or optional single-cardinality occurrence counts.
- [x] 4.5 Implement the versioned revision fingerprint encoder with canonical typed bytes, schema-aware identity, lowercase hexadecimal boundary representation, and native 32-byte database storage.
- [x] 4.6 Implement atomic stable-item get-or-create and item-locked immutable revision creation with monotonic revision numbers and unchanged detection.
- [x] 4.7 Implement typed item, revision, record, field, and schema relationship traversal with every to-many read represented by a keyset-paginated Relay connection, without generic update or delete mutations for immutable content.
- [x] 4.8 Add focused tests for typed round trips, invalid child combinations, cross-boundary references, field cardinality, fingerprint equivalence and divergence, first-item races, revision ordering, unchanged detection, and historical immutability.

## 5. Simplified Programmatic Imports

- [x] 5.1 Generate DatasetImport and DatasetImportRow resources with snapshots and migrations for `open` or `sealed` phase, expiry, idempotency identities, source provenance, pending or terminal row outcomes, candidate-record references, and progress-query indexes.
- [x] 5.2 Implement atomic import open-or-return behavior over organization, dataset, idempotency key, immutable parameters, and a same-dataset published schema.
- [x] 5.3 Define the one-row flat GraphQL input; select, test, and document safe default request, import-row, field-count, scalar-byte, and text-byte limits; and ensure oversized input, malformed scalar shapes, unsupported structures, and nesting fail before canonicalization or row acceptance.
- [x] 5.4 Implement canonical fingerprints for import opens and structurally accepted rows with native 32-byte database storage, including the external-key presence marker and persisted value, plus atomic row-key and source-position retry handling and pre-persistence duplicate-external-key rejection.
- [x] 5.5 Implement append-time schema validation that stores valid normalized candidates as pending rows and domain-invalid inputs as terminal failed provenance without opaque payloads or partial graphs.
- [x] 5.6 Use the import-row UUID as the stable target item UUID for keyless valid rows without creating an item during append.
- [x] 5.7 Implement import-locked finalization that atomically seals the accepted row set and inserts the complete unique bounded-retry row-job set, rolling back sealing on any scheduling failure and preserving safe concurrent and lost-response retries.
- [x] 5.8 Implement unique bounded-retry row jobs with terminal-row checks and atomic item-revision/outcome commits; add the responsibility-specific bounded terminalization reconciler justified by Oban 2.24.0, with exact-worker filtering, immutable row-identity arguments, overlap-preventing uniqueness, row locking and terminal recheck, sanitized `processing_retries_exhausted` outcomes for discarded or cancelled jobs, and terminal-job retention through the recovery window, without leases, fences, persisted row attempt counters, per-attempt recovery jobs, aggregate counters, or a generic recovery domain.
- [x] 5.9 Implement automatic expired-open-import cleanup under the same import lock while preserving every sealed import and finalized provenance row.
- [x] 5.10 Implement derived batch counts and lifecycle queries plus a bounded keyset-paginated Relay connection for nested and root row-outcome inspection over indexed rows, exposing row key, source position, current outcome, sanitized errors, and any resulting typed revision relationship without persisted aggregate counters or a separate processing state.
- [x] 5.11 Add focused import tests for batch and row idempotency, structurally rejected input, domain-invalid provenance, equivalent fingerprints, duplicate external keys, keyless identity, partial completion, bounded row-outcome pagination, and schema or asset scope.
- [x] 5.12 Add focused concurrency and worker tests for append/finalize and finalize/cleanup races, atomic row-job scheduling rollback, row failure before commit, retry after terminal commit, retry-exhaustion and cancellation reconciliation, reconciliation versus late terminal commit, terminal evidence retention before pruning, concurrent item revisions, derived progress, and cross-organization denial.

## 6. Integration and Verification

- [x] 6.1 Review all generated AshPostgres snapshots and migrations together, including composite keys, typed-child enforcement, asset partial uniqueness, native binary digest storage and constraints, import idempotency, expiry cleanup, row outcomes, and supporting indexes.
- [x] 6.2 Exercise the complete authenticated workflow: create and publish a schema, register and seal an asset, import mixed valid and invalid rows, retry open and append requests, finalize and process rows, inspect paginated row outcomes, and query typed historical revisions under organization authorization.
- [x] 6.3 Document required product capability bootstrap, production storage configuration, asset staging lifetime, import open lifetime, and responsibility-specific Oban schedules without selecting a storage provider.
- [x] 6.4 Run `mise run openspec.validate`, format and compile the implementation, inspect relevant logs and focused tests, and finish with `mise run verify` from a clean migrated database.

## 7. Approved code-quality review follow-through

- [x] 7.1 Return typed product errors from asset, schema, and import lifecycle actions; verify stable GraphQL codes for expected failures without exposing unexpected errors.
- [x] 7.2 Use user-before-organization locking for manager bootstrap and capability grants; exercise overlapping operations and first-item/import writes with independent database connections and committed fixtures.
- [x] 7.3 Batch distinct ready-asset lookups in record validation and cover query growth and organization scope.
- [x] 7.4 Move normalized-record validation and construction out of the revision action implementation; share record-owned operations between append and revision creation without changing fingerprints or import provenance.
- [x] 7.5 Route asset verification, staging cleanup, import processing, terminalization, and open-import cleanup through explicit internal Ash actions and code interfaces while preserving retry and claim behavior.
- [x] 7.6 Run focused checks and the repository verification gate, address compatible dependency advisory fixes needed by the gate, and record the results.

Verification on 2026-09-07: `mise run verify` passed with 143 tests, zero Dialyzer errors,
no static-analysis findings or duplicate-code clones, no retired packages or security advisories,
and successful compilation, formatting, code-generation, boundary, architecture, production-build,
and OpenSpec checks. Independent review of the application fixes found no actionable issues.

## 8. Validated simplification follow-through

- [x] 8.1 Reuse an imported immutable candidate as the new revision root, preserving scope, unchanged detection, and sealed provenance.
- [x] 8.2 Bind structurally normalized import entries to the schema without converting them back to input maps or parsing twice.
- [x] 8.3 Share the existing canonical scalar and framing encoding while preserving version-one fingerprint bytes.
- [x] 8.4 Remove unused publication-result timing metadata; retain persisted claim and publication windows.
- [x] 8.5 Move graph retirement to resource destroy actions using Ash cascade changes, preserving transactional rollback and foreign-key protection.
- [x] 8.6 Verify focused behavior, run the full repository gate and independent OpenSpec validation, and record results.

Simplification verification on 2026-09-07: `mise run verify` passed with 146 tests,
zero Dialyzer errors, no static-analysis findings or duplicate-code clones, and no retired
packages or security advisories. Compile, formatting, code generation, boundaries, architecture,
production build, and strict OpenSpec validation passed. Focused coverage preserves version-one
fingerprint bytes across all value families, candidate reuse, unchanged provenance, and
transactional rollback when a referenced record cannot be destroyed.
Independent review of `165a7ff..0448bee` found no actionable issues.

## 9. Consolidate fingerprint ownership

- [x] 9.1 Consolidate dataset fingerprint formats and private encoding helpers into one module; preserve all existing fingerprint bytes. The initial separate Ash digest type is removed by section 10.
- [x] 9.2 Run the repository gate and independent OpenSpec validation, then record the results.

Consolidation verification on 2026-09-07: `mise run verify` passed with 146 tests,
including unchanged version-one fingerprint vectors, and all compilation, static analysis,
Dialyzer, dependency audit, production-build, and OpenSpec checks.

## 10. Keep digests binary internally

- [x] 10.1 Remove the custom digest type and retain raw SHA-256 bytes in Elixir, adapters, and PostgreSQL; validate/decode registration input once and encode only GraphQL output and textual keys.
- [x] 10.2 Verify unchanged stored hashes and GraphQL string output, run the full gate and independent OpenSpec validation, and record results.

Raw-digest verification on 2026-09-07: `mise run verify` passed with 146 tests,
including raw registration/load equality, rejection of malformed and uppercase 64-character
hashes, canonical fingerprint compatibility, and unchanged GraphQL hex output. All static
analysis, Dialyzer, dependency audit, production build, and code-generation checks passed.
Existing bytea storage and length constraints are unchanged; no database migration was generated.

## 11. Approved Ponytail review simplifications

- [x] 11.1 Share one in-memory storage adapter between development and tests, preserving test controls and the storage contract.
- [x] 11.2 Derive asset summary fields from Ash resource metadata and replace the three import row lookups with one scoped keyword filter.
- [x] 11.3 Run the repository gate and independent OpenSpec validation, then record results.

Ponytail verification on 2026-09-07: `mise run verify` passed with 146 tests and all
compilation, static analysis, Dialyzer, dependency audit, production-build, and code-generation
checks. Independent OpenSpec validation passed all three items. Independent review found no
actionable issues. Existing tests cover the shared adapter, safe summaries, and import identities.

## 12. Approved repository audit simplifications

- [x] 12.1 Merge the in-memory adapter and its private store, preserving deadlines, fencing, and test controls.
- [x] 12.2 Reuse the existing independent-connection helper for OIDC race tests and share GraphQL request assertions in ConnCase.
- [x] 12.3 Replace product grant lookup/insertion with Ash bulk upsert while preserving manager checks and transactional failure handling.
- [x] 12.4 Run the repository gate and independent OpenSpec validation, then record results.

The user explicitly retained the foundation GraphQL declarations and metrics scaffold for
planned future work. They and their dependencies are outside this simplification pass.

Repository audit follow-up verification on 2026-09-07: `mise run verify` passed with
146 tests and all compilation, static analysis, Dialyzer, dependency audit, production-build,
and code-generation checks. Independent OpenSpec validation passed all three items.
Independent code review found no actionable issues. Existing
coverage exercises storage deadlines and fencing, OIDC races, GraphQL requests, and
idempotent manager grants. The changes remove 115 application/test lines without adding
dependencies or migrations.

## 13. Explicit naming and bootstrap cleanup

- [x] 13.1 Replace ambiguous Product capability and error names with dataset/asset names and update callers and operator instructions.
- [x] 13.2 Remove unused bootstrap code interfaces and reuse equivalent organization, role, and assignment actions; preserve insert-only membership creation and bootstrap conflict guarantees.
- [x] 13.3 Clarify the deferred operator onboarding workflow without adding runtime scaffolding.
- [x] 13.4 Run the repository gate, independent review, and independent OpenSpec validation.

Bootstrap cleanup verification on 2026-09-09: compilation, formatting, code-generation,
boundary/architecture checks, static analysis, and Dialyzer passed. `mise run verify`
stopped at the dependency audit for existing `usage_rules` 1.2.7
(GHSA-j59f-776f-23hp) and `igniter` 0.8.3 (GHSA-cj7w-j579-gc42) advisories.
The remaining production build and full test suite were run separately and passed
(146 tests). Independent review found no actionable issues; independent OpenSpec
validation passed all three items. Dependency updates remain a separate follow-up;
the full verification gate is not green until those advisories are resolved.

## 14. Defer operator bootstrap and maintenance

- [x] 14.1 Create an explicitly future OpenSpec restoration change with readiness conditions and restoration requirements.
- [x] 14.2 Remove operator setup/grant helpers, custom maintenance workers/actions, and cleanup-only storage/resource support; retain expiry, authorization, immutable content, and normal processing.
- [x] 14.3 Generate and review migrations, update meaningful tests and operator documentation, and synchronize active specifications with the deferred scope.
- [x] 14.4 Run verification, independent review, and independent OpenSpec validation; record actual results.

Deferral verification on 2026-09-09: the reviewed migration applied successfully in the
test database; all 127 retained tests passed, including expiry rejection and finalizer
retry after claim expiry. Production compilation passed. The full `mise run verify`
passed compilation, formatting, code-generation, boundary/architecture checks, static
analysis, and Dialyzer, then stopped at the unchanged `usage_rules` 1.2.7 and `igniter`
0.8.3 advisories recorded in section 13. Production build and tests were run separately.
Independent review found one obsolete design sentence promising terminal-job recovery;
it was removed. Independent OpenSpec validation passed all four items. The full gate
remains blocked by those dependency advisories. This pass removes 1,965 net application/
test lines. The migration removes maintenance metadata and indexes, preserves content
and provenance, and deliberately requires a reviewed forward migration to restore lost
metadata instead of offering an unsafe rollback.

## 15. Approved Ash locality and built-in simplifications

- [x] 15.1 Inline the six generic draft-edit callbacks and permission-check callback, preserving transactions, locks, and authorization; call internal actions through resource code interfaces.
- [x] 15.2 Use built-in comparison for future session issuance while retaining the cross-field validation module's ability to support atomic/batch callbacks.
- [x] 15.3 Replace latest-version record loading with a maximum aggregate, asset set comparison with a count aggregate, and fingerprint helper work with native UUID/iodata functions.
- [x] 15.4 Verify retained behavior, concurrency, and version-one fingerprint bytes; run the full gate, independent review, and independent OpenSpec validation.

Verification on 2026-09-09: all 127 tests passed, including schema edit/publication
concurrency and version-one fingerprint coverage. All five retained record-type/field
update/destroy and session-revocation actions built valid fully atomic changesets.
Production compilation and independent OpenSpec validation (four items) passed.
The full gate passed formatting, code generation, boundary checks, zero compile
cycles, static analysis, and Dialyzer, then stopped at the unchanged `usage_rules`
1.2.7 and `igniter` 0.8.3 advisories recorded in section 13. Production build and
tests were run separately. Independent review found no remaining issues. Internal
draft-edit code interfaces live on their resources to avoid a domain/resource
compile dependency cycle. Removed the newly empty source directories.

## 16. Approved composable database operations

- [x] 16.1 Move publication-start and claim-release eligibility into atomic filtered asset updates, preserving claim fencing and public errors.
- [x] 16.2 Check root membership in the publication update and set publication time in the action while retaining the parent-schema lock.
- [x] 16.3 Lock existing items on their first lookup and retain uniqueness-conflict retries for concurrent creation.
- [x] 16.4 Evaluate composable read authorization against current forbidden-response semantics; retain the existing check where filtering would change that contract.
- [x] 16.5 Verify concurrency, scope, error behavior, independent database constraints, full repository checks, OpenSpec, and independent review.

Verification on 2026-09-09: all 128 tests passed, including the new claim owner,
organization, and expiry checks; existing publication/edit and concurrent item
creation tests passed. Database-constraint tests now bypass action validation
through `Ash.Seed` to exercise the independent constraints. Production compilation
and independent OpenSpec validation (four items) passed. Independent review found
no actionable issues. The full gate passed formatting, code generation, boundary
checks, zero compile cycles, static analysis, and Dialyzer, then stopped at the
unchanged `usage_rules` 1.2.7 and `igniter` 0.8.3 advisories recorded in section 13.
Production build and tests were run separately. No new modules or anonymous
changes/validations were added.

## 17. Approved Ash feature adoption

- [x] 17.1 Share a prepared, organization-scoped published-schema read for record construction.
- [x] 17.2 Resolve ready or canonical assets through one relationship-filtered read, preserving errors and authorization.
- [x] 17.3 Combine import identity conflict lookups after the import lock, retaining row-key retry and conflict precedence.
- [x] 17.4 Select only pending row IDs during transactional job scheduling.
- [x] 17.5 Bulk-create normalized value parents and typed children by family within the existing record transaction, preserving association and rollback.
- [x] 17.6 Verify behavior, actual batching, review, full checks, and independent OpenSpec validation.

Verification on 2026-09-09: all 130 tests passed, including mixed-family identity,
child-batch rollback, conflict precedence, asset access, and scheduling rollback.
An isolated 100-text-field probe measured one value-parent INSERT and one text-child
INSERT and checked every field/value association. Production compilation and all
four OpenSpec items passed. The full gate passed compilation, formatting, code
generation, architecture, duplication and smell checks, and Dialyzer, then stopped
at the unchanged `usage_rules` 1.2.7 and `igniter` 0.8.3 advisories recorded in section
13; production build and tests were run separately. Final inline review found no
remaining issues.
