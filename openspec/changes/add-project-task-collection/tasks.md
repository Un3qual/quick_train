## 1. Generate Project Resources and Establish Scope

- [ ] 1.1 Read `proposal.md`, `design.md`, all eight delta specs, and current Forms/Datasets/Assets actions. Use `mise exec -- mix help ash.gen.domain` and `mise exec -- mix help ash.gen.resource`, then generate `QuickTrain.Projects` and the Project, ProjectItem, binding, slot/question policy, worker-access, and explicit-group resources under `lib/quick_train/projects/`.
- [ ] 1.2 Configure AshPostgres same-organization/dataset/schema/form-version references, immutable ownership, scoped unique keys, ordered group inputs, and finite field/count checks; generate migrations/snapshots with `mise exec -- mix ash.codegen add_projects` and review the generated constraints before applying them.
- [ ] 1.3 Add explicit `projects.read`/`projects.manage` policies using the existing organization-capability check; require existing source read capabilities when selecting forms/datasets, and add scoped fixtures in `test/support/` without granting production roles automatically.
- [ ] 1.4 Implement bounded draft metadata/configuration, enrollment/removal, bindings, policies, and explicit-group actions. Lock/recheck the Project parent for every child edit; reject mixed schemas, foreign definitions, duplicate cohort items/groups, and more than 100 enrollment IDs atomically.
- [ ] 1.5 Verify draft/policy/read isolation and typed relationship constraints in `test/quick_train/projects_test.exs` through direct Ash calls; run `mise exec -- env MIX_ENV=test mix test test/quick_train/projects_test.exs` and commit the project foundation.

## 2. Activate and Freeze Projects

- [ ] 2.1 Implement `Projects.ProjectActivation` to load the entire bounded graph/cohort, validate a published form/schema, complete compatible bindings, requiredness, ready source assets, fixed slot counts, distinct-item feasibility, and all question policies under the Project lock.
- [ ] 2.2 Validate explicit-group uniqueness/order/coverage, execution ceilings against form minimums, positive targets/thresholds, audience modes, and 1–120 minute leases. Reject image-intended requirements with `media_prerequisite_unavailable` until the separate verified-media capability is implemented.
- [ ] 2.3 Implement idempotent activation, pause/resume, completion/archive, and permitted post-activation title/access-override edits. Make frozen configuration and enrollment immutable; use a new project for later enrollment. Integrate completion cancellation in step 4.5 when Tasks exists.
- [ ] 2.4 Verify edit/activation races on independent connections, retries, pause transitions, no-import-enrollment drift, invalid configuration rollback, and unavailable media; rerun the focused project tests and commit activation/lifecycle behavior.

## 3. Generate Task Evidence and Worker Admission

- [ ] 3.1 Generate `QuickTrain.Tasks` and Task, TaskInput, Attempt, AttemptQuestion, AttemptInputPresentation, Response, TaskQuestionProgress, and item-coverage resources under `lib/quick_train/tasks/`; add their domain registration to `config/config.exs`.
- [ ] 3.2 Generate/review migrations and snapshots with same-project/task/version references, canonical-group identity, one response per attempt, unique offered questions/presentation positions, and the partial unique live-attempt constraint. Implement no generic public task/evidence writes.
- [ ] 3.3 Implement project-worker eligibility as a separate fail-closed check: active global User/organization, frozen member/external/both routes, open/allowlisted external access, and block precedence. Keep the shared management check unchanged and add explicit `tasks.assign`, `tasks.review`, and `tasks.results.read` policy paths.
- [ ] 3.4 Implement a typed attempt-owned work bundle and terminal receipt. Add narrowly scoped Forms/Datasets reads preserving stable published definitions, offered question IDs, actual order, exact bound values, explicit missing optionals, and no authoring/reverse/unallocated traversal.
- [ ] 3.5 Verify member/non-member/both-route cases, role separation, blocked users, ownership substitution, missing/foreign IDs, and nested form/dataset leaks in `test/quick_train/task_allocation_test.exs`; run that file with the project tests and commit the worker boundary.

## 4. Allocate Work and Enforce Leases

- [ ] 4.1 Implement the internal `Tasks.TaskSelection` contract with only balanced/explicit strategies. Canonicalize slot/item membership separately from presentation, prefer reusable task demand, anchor balanced selection on under-covered items, and consume explicit groups only with successful issuance.
- [ ] 4.2 Implement `Tasks.AttemptAllocation` with the documented lock order, skip-locked task/coverage selection, worker serialization, current eligibility checks, stale-lease cleanup, one-live-attempt constraint, and atomic question-capacity reservations/offered sets/presentation evidence.
- [ ] 4.3 Add allocation request-key persistence/conflict detection, claimed/assigned initial states, manager assignment through the same eligibility/capacity path, and typed bounded-search outcomes. Never convert contention or a worker's personal exhaustion into global completion.
- [ ] 4.4 Implement start, owner release, manager cancellation, fixed deadlines, and idempotent Oban expiration on a dedicated task-maintenance queue. Recheck database wall-clock expiry after locks; cleanup delays must not permit late access/submission or permanently reserve worker capacity.
- [ ] 4.5 Connect project pause/completion to Tasks: pause only prevents new allocations; completion immediately cancels live work and unmet tasks while preserving submitted/satisfied evidence. Ensure logical state and paginated receipts/results agree even if physical cleanup is batched.
- [ ] 4.6 Verify balanced/explicit invariants, diverse item exposure versus exact-task replication, rollback without orphan Tasks, last-slot claim races, duplicate requests, delayed expiration, fixed lease retries, and completion/submit ordering using independent connections and deliberate barriers; run allocation/project tests and commit allocation.

## 5. Collect Typed Drafts, Skips, and Submissions

- [ ] 5.1 Generate QuestionResponse, StaticOptionAnswer, and TaskInputAnswer resources/migrations. Put text/integer/decimal/boolean values in typed QuestionResponse columns with local exclusivity checks; enforce response/question uniqueness, scoped option/input references, and ranking positions without JSONB content.
- [ ] 5.2 Implement whole-question draft replacement with the Response lock and `expected_revision`, preserving local types, ownership, text precision/whitespace, finite sizes, and atomic removal of prior children when switching answered/skipped outcomes.
- [ ] 5.3 Implement published scalar/choice/ranking validation, including absent-constraint semantics, signed 32-bit integers, precise decimals, Unicode text limits, static option ownership, slot-specific selections, and complete unique ranking permutations.
- [ ] 5.4 Implement `Tasks.ResponseSubmission`: lock Task/Attempt/Response, recheck ownership/current eligibility/deadline/project state, validate every offered outcome and reject extra questions, then freeze all descendants and transition reservations/attempt state atomically. Make authorized retries return the same immutable receipt.
- [ ] 5.5 Implement explicit skip policies, server timestamps, required nonblank reasons, explanation bounds, zero target contribution, and all-skipped submission. Preserve terminal unsubmitted drafts without exposing them as accepted results.
- [ ] 5.6 Verify local-versus-submit validation, wrong-family/foreign choices, missing/extra questions, stale revisions, save/submit and submit/expiry/completion races, all-skipped behavior, and internal child immutability in `test/quick_train/task_responses_test.exs`; run focused Tasks tests and commit responses.

## 6. Add Annotations and Integrate Separate Media Prerequisites

- [ ] 6.1 Generate BoundingBox, PolygonRegion/PolygonPoint, MaskRegion, TextSpan, and attempt/question mask-attachment resources with scoped TaskInput/source-value/label references; generate and review normalized migrations and annotation limits.
- [ ] 6.2 Implement text-span code-point/exclusive-end validation against immutable bound text, overlapping-span support and exact-duplicate rejection; verify emoji, combining characters, empty/out-of-range spans, and foreign source/label references independently of media support.
- [ ] 6.3 Implement bounded normalized box and simple polygon validation: positive box area, at least three distinct polygon points, implicit closure, finite in-range coordinates, nonzero area, no crossing edges/duplicate closure, and per-question/response aggregate count limits.
- [ ] 6.4 Add attempt-owned source-asset access and mask register/finalize/attach actions preserving byte caps, immutable sealing, duplicate canonical identity, lease-limited access, and exact attachment authority. Protect task-only assets from generic asset-capability bypass and verify canonical reuse does not expose result associations.
- [ ] 6.5 Verify the separately scoped media change supplies immutable verified source/hash/dimension facts, supported serving capability, and source/mask compatibility evidence. Integrate only that contract into activation/fetch/submission; keep this item incomplete until the prerequisite exists and real integration passes. Do not add a decoder, renderer, or provider here.
- [ ] 6.6 Verify image-choice and all spatial families against the real prerequisite, including invalid masks/dimensions, lost media capability, client-dimension spoofing, foreign mask attachments, upload expiry, and response freezing. Keep gate-failure tests runnable while the prerequisite is absent; commit annotation integration only with accurate completion status.

## 7. Review, Escalate, and Rebuild Progress

- [ ] 7.1 Generate append-only ReviewDecision resources with scoped outcome references, predecessor, ordered decision identity, system/human origin, verdict/reason, and idempotency identity. Add automatic acceptance during successful submission without weakening immutability.
- [ ] 7.2 Implement `Tasks.QuestionReview` for manual accept/reject, expected-predecessor corrections, retry conflicts, self-review denial, and atomic per-question batches capped at 100 outcomes. Permit corrections in completed/archived projects without restarting work.
- [ ] 7.3 Maintain accepted/pending/skipped/rejected/live counts, effective verdicts, cumulative failure thresholds, and task open/satisfied/needs_attention/cancelled state atomically with evidence. Preserve excess accepted answers created by corrections and keep pending answers capacity-reserving.
- [ ] 7.4 Implement deliberate linked follow-up assignment from a terminal attempt for its prior worker, bypassing only ordinary same-task exclusion/escalation for unmet questions while preserving eligibility, capacity, leases, failures, and prior evidence.
- [ ] 7.5 Add responsibility-specific Oban reconciliation for question progress and item coverage, taking the same mutation locks before reading/replacing projections; derive everything from authoritative task/attempt/outcome/review evidence.
- [ ] 7.6 Verify automatic/manual partial review, conflicting corrections and retries, reviewer self-denial, skip/expiry/release escalation, cancellation neutrality, follow-up history, excess accepted evidence, and reconciliation/evidence races in `test/quick_train/task_review_test.exs`; run the focused suite and commit review/progress.

## 8. Read Results and Produce Immutable Exports

- [ ] 8.1 Add bounded accepted/audit reads and typed relationships with `tasks.results.read`, exact input/form/schema/revision/worker/presentation provenance, direct scoped owner lookups, and no canonical answer, account secrets, compensation fields, or mutable live drafts.
- [ ] 8.2 Generate ResultExport and typed snapshot-membership resources for terminal attempts, submitted outcomes/effective decisions, and included review history; add request-key identity, accepted/audit modes, inclusive task-ID range selection, lifecycle, and transactional Oban enqueue.
- [ ] 8.3 Implement atomic committed snapshot selection under repeatable-read isolation, requester reauthorization, the 100,000-entry bound, and sealed membership reused on retries. Use the smallest documented Repo isolation helper only if Ash cannot express this transaction boundary.
- [ ] 8.4 Implement deterministic format-versioned JSONL streaming over sealed membership, exact decimal/hash encoding, frozen provenance only, 256 MiB/configured-asset bounds, and bounded temporary-file cleanup. Exclude mutable titles/current verdicts outside the pinned snapshot.
- [ ] 8.5 Extend `lib/quick_train/assets/storage.ex` with the minimal bounded server-side staging-write capability and explicit unavailable behavior; implement the in-memory contract double without pretending to provide HTTP. Publish through existing hash/size sealing and atomically associate one ready export artifact.
- [ ] 8.6 Implement authorized export state/download access and idempotent worker retry/recovery; verify byte-publication-before-state crashes, unavailable adapters, revoked result permissions, no partial downloads, and generic asset-read bypass denial.
- [ ] 8.7 Verify snapshot/correction and uncommitted-submission races, stable retry bytes, accepted/audit differences, more-than-one-page traversal, exact JSONL provenance, selection/output ceilings, and source/mask/export authorization in `test/quick_train/task_results_test.exs`; run the focused suite and commit results/exports.

## 9. Complete the GraphQL Contract and Operational Integration

- [ ] 9.1 Add Projects/Tasks to `lib/quick_train_web/graphql/schema.ex` and expose deliberate typed project lifecycle/configuration, fetch/assign/follow-up/start/release/cancel, bundle/receipt, save/submit, review/correct, results, and export actions. Keep private persistence and unrestricted derivations off the allowlist.
- [ ] 9.2 Apply Relay keyset pagination default 50/max 100 to every public collection including typed answer children; retain stable authored/display/review order, current signed 32-bit Int semantics, HTTP body limits, sanitized errors, and documented retry/no-work outcomes without adding aggregate query complexity machinery.
- [ ] 9.3 Wire worker queues, log only sanitized operational IDs/errors, and document capability provisioning and prerequisite-dependent image/storage behavior in this change's design. Verify no production role acquires implicit grants and the separate operator-bootstrap change is not required.
- [ ] 9.4 Cover complete organization-member and external-user collection flows, direct assignment, partial question sets/review, blocked/revoked access, closed-project behavior, nested cross-scope attempts, and export denial/success in `test/quick_train_web/graphql/project_task_collection_test.exs`.
- [ ] 9.5 With the separately selected real storage/media prerequisites available, verify compliant reachable upload/download descriptors, mask/source compatibility, and export delivery. Keep this integration item unchecked while only in-memory contract tests pass; do not implement the provider or media renderer in this change.

## 10. Verify, Reconcile Artifacts, and Commit

- [ ] 10.1 Verify generated migration up/down/reapply on a disposable database containing representative existing published forms/datasets plus project/attempt/submission/review/export records. Check original identities/content survive additive up migrations, and document preservation of real evidence during deployment rollback.
- [ ] 10.2 Run the focused Projects/Tasks/GraphQL suites and meaningful independent-connection concurrency cases; fix confirmed failures without adding implementation-text tests or unrelated refactors. Ensure all eight capability deltas have implemented and verified acceptance coverage.
- [ ] 10.3 Reconcile proposal/design/specs/tasks and the source architecture cross-links with the final implementation. Leave media/storage-dependent items incomplete until actual integration succeeds and keep Finance/Reputation outside scope.
- [ ] 10.4 Run `mise run openspec.validate`, then `mise run verify`; record actual results, commit the finished implementation, and archive only after every task and accepted integration prerequisite is complete.
