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

## 18. Approved Ponytail review cuts

- [x] 18.1 Remove import append's transaction resource inventory and schema-edit resource-list plumbing while preserving parent locks and rollback.
- [x] 18.2 Replace the duplicated allowlisted failure conversion with `Atom.to_string/1`.
- [x] 18.3 Return import processing results directly to Oban and update existing worker assertions.
- [x] 18.4 Run verification, independent OpenSpec validation, and an inline final review.

Verification on 2026-09-09: all 130 tests passed, including schema-edit concurrency,
import rollback and worker retries, and sanitized asset failures. Production
compilation and all four OpenSpec items passed. The full gate passed compilation,
formatting, code generation, architecture, static analysis, and Dialyzer, then
stopped at the unchanged `usage_rules` 1.2.7 and `igniter` 0.8.3 advisories recorded
in section 13. Production build and tests ran separately. Final review was inline;
the implementation removes 29 lines with no new modules or tests.

## 19. Approved import performance improvements

- [x] 19.1 Reuse published schema fields and load only value families present in a candidate.
- [x] 19.2 Bulk-insert row jobs in bounded batches inside the locked sealing transaction, using the import phase as the one-time enqueue boundary.
- [x] 19.3 Remove obsolete worker uniqueness and single-row enqueue behavior, and document the future recovery boundary.
- [x] 19.4 Verify mixed-family fingerprints, concurrent finalization, and rollback after job insertion.
- [x] 19.5 Compare query counts, run the verification gate and independent OpenSpec validation, and review inline.

Verification on 2026-09-09: all 132 tests passed, including a 1,001-row concurrent
finalization across batches, rollback after actual job insertion followed by a
successful retry, and unchanged fingerprints for all six candidate value families.
A temporary isolated SQL trace measured text-only row processing at 16 statements
(previously 22), and 1,000-row finalization at 10 statements (previously 3,008).
The local finalization sample decreased from 2.25 seconds to 51 milliseconds;
10,000 rows took 28 statements and 423 milliseconds. The probe verified exactly
one job for every expected row at 100, 1,000, and 10,000 rows. Timings are local
test measurements, not production benchmarks. Production compilation and all four
OpenSpec items passed. The full gate passed compilation, formatting, codegen,
architecture, static analysis, and Dialyzer, then stopped at the unchanged
`usage_rules` 1.2.7 and `igniter` 0.8.3 advisories recorded in section 13. Production
build and tests ran separately. Final inline review found no remaining issues.
GraphQL complexity limits were outside that performance-fix batch; section 20 records their subsequent approval and implementation.

## 20. Approved correctness and GraphQL review fixes

- [x] 20.1 Preserve whitespace and empty text using Ash constraints at input and persistence.
- [x] 20.2 Require authorized-parent reads for all six typed-value resources.
- [x] 20.3 Enable HTTP complexity limits and charge both root and nested connections for explicit or default page sizes.
- [x] 20.4 Verify text round trips, import identity, denied direct reads, and bounded HTTP GraphQL execution.
- [x] 20.5 Run the full verification gate, independent OpenSpec validation, and final inline review.

Verification on 2026-09-09: all 135 tests passed. Coverage includes exact text and
empty-string round trips, unchanged candidate fingerprints, import retry identity,
denied direct reads for all six typed resources, and HTTP complexity rejection
with first, last, omitted, and null pagination at nested and root connections.
Existing authenticated GraphQL workflows remain passing. Production compilation
and all four independent OpenSpec items passed. The full gate passed compilation,
formatting, codegen, zero compile cycles, architecture, static analysis, and
Dialyzer, then stopped at the unchanged usage_rules 1.2.7 and igniter 0.8.3
advisories. Production build and the full tests ran separately. Final inline
review found no additional issue in these fixes. No modules, dependencies, or
migrations were added; historical content is not rewritten.

## 21. Approved workflow simplifications

- [x] 21.1 Obtain validated upload access before persisting a pending asset; remove compensating registration deletion.
- [x] 21.2 Trust validated immutable candidate asset references during processing and remove the lock on already-ready canonical assets.
- [x] 21.3 Open imports with an identity upsert that preserves existing facts and handles concurrent callers through native ON CONFLICT.
- [x] 21.4 Lock schemas directly through scoped relationship filters and retain fresh child reads after locking.
- [x] 21.5 Verify failures, concurrent opens, sealed retries, candidate reuse, schema publication protection, and the full project gates.

Value ID generation and sorted bulk-insert correspondence remain unchanged.

Verification on 2026-09-09: all 137 tests passed, including simultaneous import
opens and conflicting schemas on independent database connections, preservation
of sealed import facts on retry, and registration failure without a pending row.
Existing candidate reuse, asset convergence, direct-write asset rejection, and
schema publication protection tests passed. Production compilation and all four
OpenSpec items passed independently. The full gate passed formatting, compilation,
codegen, zero compile cycles, architecture/static checks, and Dialyzer, then stopped
at the unchanged usage_rules 1.2.7 and igniter 0.8.3 advisories recorded above;
production compilation and the full test suite ran separately. The final inline
review found no additional issue. Production code/configuration decreased by
40 lines; no production modules, dependencies, or migrations were added.


## 22. Local CodeRabbit review follow-through

- [x] 22.1 Evaluate all 28 suggestions against implementation, installed dependency source, and current/future specifications.
- [x] 22.2 Fix required asset configuration access, simplify redirect validation, and normalize invalid read-descriptor returns while removing the unreachable upload clause.
- [x] 22.3 Reject PDF publication without adding a parser or sanitizer; test both text and binary PDF payloads and misleading declarations.
- [x] 22.4 Check import field count before allocating normalized input maps, log unexpected authorization failures without raw error details, and isolate the missing-subject test assertion.
- [x] 22.5 Remove stale cleanup and reconciliation promises from current planning artifacts.
- [x] 22.6 Run verification and inspect the final diff.

Review disposition (CLI output order within each scope):

| Scope / finding | Decision and evidence |
| --- | --- |
| lib 1: missing read/claim configuration | Use `Keyword.fetch!` for required configuration. |
| lib 2: timeout mailbox replies | No change: OTP 29 `gen.erl` uses process aliases and demonitor/flush on timeout. |
| lib 3: ignored redirect descriptor | Remove the unused argument; approved HTTPS destinations remain the invariant. |
| lib 4: GraphQL digest bytes | No change: schema middleware hex-encodes both Asset and AssetSummary digests; GraphQL tests cover output. |
| lib 5: PDF active content | Reject PDF publication as unsupported, including a plain-text declaration; no speculative sanitizer. |
| lib 6: malformed read response | Return the same controlled descriptor error as upload access. |
| lib 7: unreachable false clause | Remove it; the existing error tuple branch handles an unenforced cap. |
| lib 8: terminal verification retries | No change: finalization commits terminal failures and returns a successful result to the worker. |
| lib 9: missing byte cap | Fetch required keys explicitly before issuing access. |
| lib 10: field deletion errors | No change: `Ash.transact` rolls back returned error tuples (`rollback_on_error?: true`). |
| lib 11: explicit private user | No change: use Ash's private-by-default attribute convention. |
| lib 12: silent authorization failures | Log framework/database failure classes while remaining fail-closed; expected denials stay quiet and raw exception details stay private. |
| lib 13: allocation before field cap | Check count before mapping; preserve structural rejection order and normalized request-size accounting. |
| lib 14: distinct text-limit code | No change: both cases deliberately reject scalar-budget violations; no contract requires separate codes or field diagnostics. |
| lib 15: error-code allowlist | No change: Values returns explicit atoms or the deliberately constructed `required_missing` field-key string, not arbitrary exception messages. |
| lib 16: candidate retry comment | No change: immutability is already a documented invariant; mutable candidate support is not planned. |
| lib 17: enum callback arity | No change: installed Ash.Type.Enum overrides `storage_type/0`; Ash.Type's arity-1 callback delegates to it. |
| lib 18: Decimal/DateTime aliases | No change: consumers use qualified DatasetValue names, not conflicting scalar aliases. |
| lib 19: trigger indexing/cost | No change: all six child foreign keys have unique indexes; the prior performance pass measured imports. No new projection or trigger rewrite without evidence. |
| lib 20: bulk job batching | No change: Finalize chunks at 1,000 under the sealing lock and row processing is idempotent. |
| lib 21: oversized global body limit | No change: actual configured limit is 512 KiB, below the suggested 8 MB; imports use the same GraphQL route. |
| lib 22: null value family | No change: the field family is NOT NULL and required relationships are protected by foreign keys. |
| lib 23: irreversible function DDL | No change: resource custom statements and migration down already drop both functions. |
| test 1: scheduler restoration | No change: no configured scheduler value exists; this synchronous test removes its override to restore the actual default. |
| test 2: dynamic table truncation | No change: committed fixtures are covered by the existing cascade roots; no uncovered persisted table was identified. |
| test 3: missing-subject assertion order | Move the assertion before organization deactivation to make the independent case clearer. |
| openspec 1: reconciliation promise | Remove the obsolete current-scope promise (and adjacent staging-cleanup promise). |
| openspec 2: periodic import deletion | Replace with current expiry enforcement and retention until the deferred maintenance change. |

Verification on 2026-09-09: all 139 tests pass. Production compilation, all four
OpenSpec items, formatting, code generation, zero compile cycles, static and
architecture checks, and Dialyzer pass. `mise run verify` stops at the unchanged
LOW usage_rules 1.2.7 (GHSA-j59f-776f-23hp) and igniter 0.8.3
(GHSA-cj7w-j579-gc42) advisories; the full tests and production compilation ran
separately. No production modules, dependencies, or migrations were added.


## 23. PR review thread follow-through

- [x] 23.1 Fetch every review thread and top-level suggestion at `cca01c7`, including historical snapshot nitpicks; validate against current code and specifications.
- [x] 23.2 Reject tag-like markup rather than selected HTML elements, validate PNG framing/checksums without decoding, and reject expired descriptors.
- [x] 23.3 Route every pending finalization through verify-and-publish so canonical reuse still checks its staging; preserve late-publication retries and claim fencing.
- [x] 23.4 Verify the focused regressions and complete project checks. Push without waiting for another review cycle.

Disposition of the fetched comments:

- OIDC retry (`3972755151`): no change; the authentication spec explicitly prohibits reuse after failed or interrupted exchange.
- Actor fingerprint (`3972759407`): no behavior change; the initiating actor is immutable provenance, separate from the organization/dataset/key uniqueness scope. Clarify the design.
- In-memory read-token retention (`3972760513`): deferred with the explicitly removed maintenance workflows; record this development-adapter limitation rather than restoring cleanup code.
- Blank candidate external key (`3972760799`): no change; a live probe confirms Ash's default string constraints turn empty and whitespace-only strings into nil. The presence validation then requires an item ID.
- Transient sealed-storage error (`3972762441`): the preliminary sealed-read branch is removed. Unknown errors after publication starts still retain the bounded claim because storage may still be running.
- HTML denylist (`3972826959`): replace with a general tag-like markup rejection for the plain-text path; cover img, input, and custom elements.
- PNG header (`3972826965`): validate the complete header, supported header fields, chunk lengths/CRCs, nonempty IDAT, and terminal IEND with Erlang's CRC builtin; use a real PNG fixture. No decompression or new dependency.
- Decimal exponent (`3972826974`): no change; the installed Decimal 3.1.1 parser rejects `1e999999999`, `1e131072`, and `1e-16384` before expansion. Its default coefficient/exponent and rendering limits also fit PostgreSQL numeric. Retain these library limits.
- Expired descriptors (`3972826983`): require expiry later than now as well as at or below the requested bound.
- Canonical adoption (`3972987084`): remove the shortcut, always verify staged bytes before conditional publication/reuse, and retain existing duplicate/concurrency behavior.
- Snapshot nitpicks (`5608339043`): no change; snapshots are historical migration inputs. The latest asset snapshot and removal migration already remove both obsolete fields.

Verification on 2026-09-09: 143 tests pass, including the new HTML/PNG/canonical
adoption regressions, expired descriptor checks, and existing late-publication
and concurrent-convergence tests. Production compilation and all four OpenSpec
items pass. Formatting, code generation, zero compile cycles, static/architecture
checks, and Dialyzer pass. The full verification gate stops at the same LOW
usage_rules/igniter advisories documented above; tests and production compilation
ran separately. No production modules, dependencies, or migrations were added.

## 24. Current PR feedback and dependency advisories

- [x] 24.1 Reject malformed descriptor header entries before pending asset insertion (3973196766).
- [x] 24.2 Reject unsupported GIF instead of adding another image container parser (3973196771).
- [x] 24.3 Reject PostgreSQL-unsupported NUL text during import and direct revision normalization (3973196778).
- [x] 24.4 Remove the unused redirect helper and require provider-enforced direct endpoints; no proxy or redirect workflow is added (3973196783).
- [x] 24.5 Reject PDF signatures in the first 1,024 bytes, including prefixed payloads (3973196789).
- [x] 24.6 Patch usage_rules to 1.2.8 and igniter to 0.8.4 for CVE-2026-82710 and CVE-2026-82584, with no transitive dependency changes.
- [x] 24.7 Run focused regressions, the complete verification gate, and independent OpenSpec validation.

Previously assessed unresolved comments retain their section 23 dispositions. This
pass adds no maintenance workflow, redirect machinery, or image decoder. Existing
stable toolchain pins remain compatible with these two dependency patches.

Verification on 2026-09-09: 60 focused tests and all 146 full-suite tests passed.
`mise run verify` passed, including static analysis, Dialyzer, production compilation,
and a clean dependency advisory/retirement audit. Independent
`mise run openspec.validate` passed all four artifacts.

## 25. Opaque-file MVP and current PR feedback

This approved scope revision supersedes earlier image inspection, active-format
rejection, and development in-memory adapter tasks and review dispositions.

- [x] 25.1 Remove PNG/JPEG/GIF/PDF parsing, sniffing, image bounds, and active-content checks; retain size/hash verification and immutable declared metadata (3973402890).
- [x] 25.2 Reject NUL import row/external identifiers before candidate construction (3973402896).
- [x] 25.3 Synchronize the authentication spec with introspectable, policy-protected dataset/asset fields (3973402901).
- [x] 25.4 Remove the misleading development adapter default; fail clearly until a reachable HTTP provider is configured (3973402903).
- [x] 25.5 Record opaque download response requirements and defer parsing/rendering/HTTP integration in the future architecture change.
- [x] 25.6 Run focused tests, full verification, and independent OpenSpec validation before pushing.

Existing nullable image-dimension columns are retained without an MVP writer; no
new schema or migration is needed. Previously assessed unresolved findings remain
unchanged except where this explicit MVP revision supersedes format checks.

Verification on 2026-09-09: 42 focused tests passed, then the full `mise run verify`
gate passed with 141 tests, static analysis, Dialyzer, production compilation, and
a clean dependency audit. Independent strict OpenSpec validation passed all four
artifacts. Removed format-parser tests account for the lower test count.

## 26. Deterministic asset errors

- [x] 26.1 Handle canonical storage conflicts through the existing failed transition as `asset_identity_conflict`, clearing the claim and making retries terminal (3973625365).
- [x] 26.2 Reject PostgreSQL-incompatible media-type text before requesting storage access (3973625375).
- [x] 26.3 Verify focused concurrency/validation regressions, the full gate, and independent OpenSpec validation.

These fixes preserve opaque downloads and deferred HTTP/format-aware work. They add
no new module, storage operation, recovery workflow, or schema change. Older review
findings retain their recorded dispositions and approved scope boundaries.

Verification on 2026-09-09: all 10 focused asset lifecycle tests passed. The full
`mise run verify` gate passed with 143 tests, static analysis, Dialyzer, production
compilation, and a clean dependency audit. Independent strict OpenSpec validation
passed all four artifacts.

## 27. Import open-key validation

- [x] 27.1 Deduplicate comments 3973754497 and 3973754504 and reject NUL in import idempotency keys through Ash string constraints on the open argument and persisted attribute.
- [x] 27.2 Verify controlled rejection without batch reservation, normal idempotent retries, the full gate, and independent OpenSpec validation.

No custom type, callback, migration, or lifecycle is added. Older unresolved review
findings retain their documented dispositions and deferred-scope boundaries.

Verification on 2026-09-09: all 19 focused import tests and all 144 full-suite tests
passed. `mise run verify` passed including static analysis, Dialyzer, production
compilation, and a clean dependency audit. Independent strict OpenSpec validation
passed all four artifacts.

## 28. Dataset metadata validation

- [x] 28.1 Reject NUL in dataset keys and names with built-in Ash string constraints (3973830312).
- [x] 28.2 Verify field errors without persistence, corrected creation, the full gate, and independent OpenSpec validation.

The fix is local to existing resource attributes. No module, callback, migration,
or deferred capability is added; prior review dispositions remain unchanged.

Verification on 2026-09-09: seven focused schema lifecycle tests and all 145
full-suite tests passed. `mise run verify` passed, including static analysis,
Dialyzer, production compilation, and a clean dependency audit. Independent strict
OpenSpec validation passed all four artifacts.

## 29. Storage-compatible input boundaries

- [x] 29.1 Reject NUL in record-type and field keys/names using built-in Ash constraints (3973954102).
- [x] 29.2 Bound normalized and persisted integer values to signed 64-bit storage (3973954110).
- [x] 29.3 Limit indexed dataset/schema/import/item identifiers to 512 UTF-8 bytes at resource and relevant action boundaries (3973954116).
- [x] 29.4 Disable trimming on the supplied asset hash to preserve exact-input validation (3973954122).
- [x] 29.5 Run focused boundary tests, the full verification gate, and independent OpenSpec validation.

No new modules or migrations are introduced. Previous review dispositions and
opaque-download/deferred-operator scope remain unchanged.

Verification on 2026-09-09: 58 focused tests passed, followed by the full gate
with 150 tests, including signed 64-bit boundary round trips. `mise run verify`
passed static analysis, Dialyzer, production compilation, and the dependency audit.
Independent strict OpenSpec validation passed all four artifacts.

## 30. Remaining input and contract corrections

- [x] 30.1 Bound source positions with built-in Ash integer constraints before callbacks and persistence (3974067934).
- [x] 30.2 Reject NUL in direct revision external-key arguments and item attributes (3974067941).
- [x] 30.3 Align import asset eligibility with the approved opaque-download contract (3974067944).
- [x] 30.4 Verify focused regressions, the full gate, and independent OpenSpec validation.

No custom validation module, migration, format parser, or new workflow is added.
Prior findings retain their recorded dispositions.

Verification on 2026-09-09: all 36 focused tests and all 152 full-suite tests passed.
`mise run verify` passed static analysis, Dialyzer, production compilation, and a
clean dependency audit. Independent strict OpenSpec validation passed all four
artifacts.

## 31. GraphQL bigint compatibility and root publication

- [x] 31.1 Use built-in GraphQL String overrides for dataset integer input/output, retaining Ash integer storage (3974177754).
- [x] 31.2 Atomically reject publication when the root's required-field aggregate exceeds the configured import cap (3974177759).
- [x] 31.3 Verify exact GraphQL bigint round trips, correction of an oversized required root, the full gate, and independent OpenSpec validation.

No custom scalar, parser, storage type, or new transaction/locking workflow is added.
Existing review dispositions and deferred scopes remain unchanged.

Verification on 2026-09-09: 12 focused tests and all 153 full-suite tests passed.
The full gate passed formatting, static analysis, Dialyzer, production compilation,
and a clean dependency audit. Independent strict OpenSpec validation passed all
four artifacts.

## 32. Direct decimal input limits

- [x] 32.1 Validate direct decimal strings and structs with Decimal.cast/1 before fingerprinting (3974405944).
- [x] 32.2 Verify controlled rejection before persistence, equivalent valid decimal identity, the full gate, and independent OpenSpec validation.

The reported string already fails Decimal 3.1.1 parsing. The valid gap was the
unchecked struct branch; use the same library coefficient/exponent limits for both
forms. No custom decimal parser, numeric-range abstraction, or dependency is added.

Verification on 2026-09-09: all 16 focused revision tests and all 154 full-suite
tests passed. The full gate passed static analysis, Dialyzer, production
compilation, and a clean dependency audit. Independent strict OpenSpec validation
passed all four artifacts.

## 33. Standard numeric GraphQL MVP contract

Approved simplification superseding the earlier full-64-bit and string-output decisions.

- [x] 33.1 Remove dataset integer GraphQL string overrides and enable Absinthe's standard 32-bit Int scalar.
- [x] 33.2 Match dataset integer and source-position Ash limits to the public numeric range, retaining existing bigint columns.
- [x] 33.3 Assess comment 3974545033: the former legacy Int already accepted its 2147483648 example, but full-bigint parity was absent; the approved narrower contract resolves the mismatch without custom scalars.
- [x] 33.4 Verify numeric GraphQL boundaries, Ash rejection, the full gate, and independent OpenSpec validation.

Full 64-bit support is deferred until needed. No migration, custom scalar, client
precision workaround, or new module is added.

Verification on 2026-09-09: 40 focused tests and all 155 full-suite tests passed.
The full gate passed static analysis, Dialyzer, production compilation, and a clean
dependency audit. Independent strict OpenSpec validation passed all four artifacts.

## 34. Scoped caller item identities

- [x] 34.1 Treat direct caller-supplied item IDs as references to existing scoped items; reject nonexistent and foreign IDs identically before creation (3975017123).
- [x] 34.2 Preserve external-key creation and backend-generated keyless import identities without a new lookup or retry mechanism.
- [x] 34.3 Verify foreign/missing equivalence, existing keyless revisions, import behavior, the full gate, and independent OpenSpec validation.

This changes direct supplied-ID creation to prevent an existence probe. It does not
change value IDs or import-generated item IDs. No module or migration is added.

Verification on 2026-09-09: 38 focused tests and all 156 full-suite tests passed.
The full gate passed static analysis, Dialyzer, production compilation, and a clean
dependency audit. Independent strict OpenSpec validation passed all four artifacts.

## 35. Publication result contract

- [x] 35.1 Require returned sealed key and verified facts to match the publication request before committing readiness; return `invalid_storage_result` for malformed adapter results (3975328661).
- [x] 35.2 Verify missing/wrong keys and mismatched facts never mark an asset ready, the full gate, and independent OpenSpec validation.

The fix uses pattern matching without another storage read. An invalid response
retains the bounded claim because publication may have occurred; deferred recovery
scope is unchanged. Matching assertions cannot prove a dishonest adapter wrote bytes;
the adapter still owns publication and verification under its existing contract.

Verification on 2026-09-09: all 12 focused tests and all 157 full-suite tests passed.
The full gate passed static analysis, Dialyzer, production compilation, and a clean
dependency audit. Independent strict OpenSpec validation passed all four artifacts.
