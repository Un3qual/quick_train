## 1. Attempt-owned answers

- [x] 1.1 Consolidate Response into Attempt, migrate evidence/provenance, and update direct/API consumers.
- [x] 1.2 Verify draft revision, submission, immutability, review, and export behavior.

## 2. Derived progress state

- [x] 2.1 Replace stored attention/task state with Ash calculations and remove their write paths.
- [x] 2.2 Verify allocation, completion, corrections, and reconciliation.

## 3. Version-level form snapshots

- [x] 3.1 Replace individual immutable Forms membership with sealed form-context eligibility and migrate existing snapshots.
- [x] 3.2 Verify filters, exact counts, snapshot retries, and empty context.
- [x] 3.3 Make JSONL key ordering deterministic across runtime restarts, preserving published assets and restarting unpublished publication from the same sealed records.

## 4. Explicit allocation

- [x] 4.1 Initialize coverage at activation and isolate explicit group/coverage locks.
- [x] 4.2 Verify ordering, concurrency, and coverage preservation.

## 5. Collection authorization boundary

- [x] 5.1 Move collection context reads/authorization into Tasks and restore foundation domain ownership.
- [x] 5.2 Verify paginated worker/result context and denied cross-scope/reverse traversal.

## 6. Closeout

- [x] 6.1 Synchronize canonical and deferred-media specifications with the final design.
- [x] 6.2 Run migration checks and mise run verify, and commit the completed work.

## Verification

- `mise run verify` passed: 354 tests, codegen/format/compile checks, no compile cycles, static analysis, Dialyzer, dependency audit, and production compilation.
- Strict OpenSpec validation passed for all 15 specifications and changes.
- A disposable database seeded from `5dca6dd` retained draft revisions, submitted outcome ownership, historical response IDs, and accepted/audit/empty export records through migration.
- Rollback and reapplication succeeded in that disposable database. Forward verification covered idle-project coverage backfill, published asset identity/hash preservation, pending-publication restart, and identical regenerated hashes in separate runtime launches.
