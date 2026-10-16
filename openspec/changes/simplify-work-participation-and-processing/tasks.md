## 1. Participation and durable reservations

- [ ] 1.1 Start with supported Ash generators for necessary resource/schema edits, then rename the current resource and generated interfaces to TaskParticipation. Use active/submitted/returned/expired/cancelled, operation and nullable started_at as designed; update current callers, result/audit metadata and terminal-state filters, and disposable fixtures directly under the [task-results delta](specs/task-results/spec.md).
- [ ] 1.2 Implement deadline-aware Task capacity and worker-slot cleanup with native Ash queries/actions and existing lock helpers. Keep fixed deadline/idempotency, per-Task history exclusions and the one-active-Task-per-Project/worker cap. Remove ExpireAttempt scheduling/worker and any unused queue configuration.
- [ ] 1.3 Separate worker read/start/save protection from Task capacity locking, including bound-value reads and source-download authorization under the [task-results delta](specs/task-results/spec.md). Audit all typed-child paths and verify independent workers' source reads, deadline checks after waits, last-slot, overdue-worker-slot, save/submit/terminalization, project closure and revoked-authority races with actual concurrent transactions; preserve scoped access, draft privacy and descriptor issuance outside transactions.
- [ ] 1.4 Update scoped domain/GraphQL surfaces and organization authoring guidance with Project/Task/Question examples, independent worker completion and the effect of skips on submission quotas. Verify no unissued source access or per-question reservation is exposed. Process one worker's small question set/drafts together with atomic submission and no per-question processing/checkpoint lifecycle, preserving existing typed-child/API bounds.

## 2. Effective review defaults

- [ ] 2.1 Derive effective review status from explicit human decisions or frozen submission/review mode using Ash facilities. Remove system-acceptance row creation and origin-only fields/actions that have no remaining purpose.
- [ ] 2.2 Preserve first-decision absence, successor/predecessor and UUID retry checks, attribution and scoped authorization. Verify competing first reviews, corrections after closure, skip rejection and self-review exclusion.
- [ ] 2.3 Use the shared effective verdict in review reads, receipts, accepted-result filters and export snapshot selection. Verify automatic accepted status with absent decision reference, manual pending status, human override and no automatic human-quality evidence.

## 3. Bounded import processing and useful jobs

- [ ] 3.1 Use the existing worker/action conventions to replace row-job fan-out with one ProcessImport job atomically inserted at seal when pending rows exist. Preserve concurrent/replayed seal behavior and empty-import completion.
- [ ] 3.2 Stream pending rows in bounded pages through the existing per-row process action. Verify crash/retry after a committed row, expected permanent failure isolation, transient failure rollback, no skipped pending rows and honest retry-exhaustion progress. Benchmark large imports and memory/query behavior before considering chunks.
- [ ] 3.3 Remove ProcessImportRow and unused VerifyAsset plus orphan enqueue/queue paths; preserve synchronous asset verification and export jobs. Keep deferred maintenance documentation aligned with import-scoped recovery.

## 4. Integration verification

- [ ] 4.1 Reconcile reputation integration names, neutral-expiry behavior and no-closure-refresh assumptions with the dependent change; verify pending reputation work cannot change native submission demand or issued-work ownership.
- [ ] 4.2 Run focused native collection/import/review checks using many small Tasks and varying worker populations, verify atomic all-question submission, inspect logs, synchronize the implemented delta specs into the main specs, run mise run openspec.validate, and finish with mise run verify before merge/archive. Commit coherent implementation steps; do not implement reputation or Finance implicitly.
