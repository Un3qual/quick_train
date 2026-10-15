## Context

See the [proposal](proposal.md) for scope. The current Tasks domain stores Attempt rows, fixed deadlines and immutable input presentations. It schedules one ExpireAttempt job per issuance, uses shared Task locks on worker reads/saves, and stores system acceptances for automatic review. Dataset finalization schedules one ProcessImportRow job per pending row. The existing VerifyAsset worker has no runtime enqueue caller; asset finalization already verifies synchronously.

## Goals / Non-Goals

**Goals:** preserve exact issuance, authorization, durable retries and immutable submissions with fewer lifecycle states, shared locks and jobs. Implement the approved native collection contracts before reputation hooks depend on them.

**Non-Goals:** a reservation service, new queue framework, per-question allocation, multi-Task prefetch, new reviewer workflow, Finance or runtime changes during planning. Retain the current single pinned form per Project. Do not add legacy aliases, data backfills or rollout machinery for this unreleased product.

## Decisions

### One Task participation, one reservation

Rename the native Attempt resource/API to TaskParticipation. Use `state: active | submitted | returned | expired | cancelled`, retaining `operation: fetch | assign`, nullable `started_at`, fixed `deadline`, `terminal_at`, scope/worker/requesting-actor references, request UUID and draft revision. Remove separate claimed/assigned/in_progress state values; origin and start are orthogonal facts. Use returned instead of released as the terminal label. No additional status columns or separate Lease resource are needed. Issuance may remain unstarted, especially for direct assignment; deliberate start or first save records start without an active-state transition. A worker initiating the ordinary self-service request deliberately takes that Task; fetching unused future work is not yet supported and must not silently become a reliability failure or consume historical Task eligibility.

One participation reserves one of the Task's frozen submission slots and covers its entire pinned form. Keep the one-active-participation-per-Project/worker limit as a separate concurrency cap and keep ordinary exclusion of any previously participated Task. Project-wide membership/eligibility is not a Project reservation. Guide organizations to create many small Tasks over independent inputs with the same small repeated form. For example, 1,000 images with three requested submissions means 1,000 Tasks and 3,000 worker work units. Workers may complete ten Tasks and stop; others fill remaining capacity. Allowed skips count toward submissions and therefore do not guarantee three actual answers per question. Actual-answer quotas remain future work.

### Process a small Task as one unit

Use ordinary native reads to load one worker's small Task question set and own draft outcomes together, then validate and submit it atomically. Keep existing per-question draft saves and revision checks; they do not require per-question processing jobs, checkpoints or a resumable submission state machine. Preserve public Relay conventions and bounded source/typed-child traversal: a few questions do not bound one answer's size. Large multi-worker answer populations, reports, exports, imports and worker histories keep their existing bulk processing bounds. Initial throughput workloads use many small Tasks and varying worker counts; giant-form optimization is not an initial acceptance target. This adds no hard question-count limit.

### The database deadline frees capacity

Keep the existing configured fixed duration appropriate to the work; no new seconds/minutes default is approved. Under the Task capacity lock, count submitted participations plus active participations with `deadline >` one post-lock database cutoff. Lazily record expired rows while selecting a Task and when an owner transition or Project closure encounters them. Before issuance, also expire an overdue participation occupying the existing worker/Project unique active slot, so physical-state uniqueness cannot block replacement. Maintain a canonical order for multiple Task locks during any such cleanup; do not acquire a second Task out of order while holding the first. Candidate/worker revalidation remains transactional and retries must not extend deadlines.

All protected worker actions recheck the deadline after waits even if the physical state remains active. Expiration cleanup is not needed to free logical capacity or deny late submission; remove the per-participation ExpireAttempt worker and enqueue path. No periodic sweep is needed for allocation correctness. Scoped inspection derives effective expiry from the deadline and identifies whether terminalization has been recorded, without mutating on a read or exposing overdue work content. Actual persisted expired rows remain necessary before reviewer classification. A classifier can invoke the same authorized, locked terminalization when inspecting/classifying overdue work rather than wait for a cleanup job. Deadline passage itself is neutral to reputation. The reputation change owns later excused/unexcused classification and its refresh.

An in-memory reservation could disappear on restart or disagree across nodes; do not use it as authority. A client cache grants no capacity. Multi-Task prefetch and treatment of unopened prefetch remain deferred; this change serves one Task bundle at a time.

### Narrow locks without weakening owner checks

Use Ash actions/queries and the repository's existing database lock helpers. Keep Project protection against closure/frozen-contract changes. Worker bundle/source reads, optional start and draft save lock the owning participation, without a shared Task write-conflicting lock. Saves retain question-response/descendant coordination and optimistic revision checks. Submission and capacity-changing transitions retain Project → Task → participation → selected response ordering; key operations retain their Task coordination. Recheck current actor/owner, scoped authority, Project lifecycle and deadline after waits. The global NotStaff rule remains owned by the reputation plan and applies across both paths once implemented; this change must not create a bypass.

Keeping the current broad helper everywhere would serialize independent workers on the same Task. Removing all locks would permit draft writes after submission or closure. Split helpers by the invariants each action protects and verify save-vs-submit/terminalization, closure, assignment and last-slot races before accepting the narrower path.

### Automatic acceptance is a default, human review is a fact

Derive effective verdict from the latest explicit human decision; otherwise submitted answered outcomes in automatic mode are accepted and those in manual mode are pending. Skips are non-reviewable. Persist no system-origin ReviewDecision. Frozen review mode plus the immutable submission explains automatic acceptance; it is not substantive human-review quality evidence.

Reuse selected QuestionResponse locks and native Ash calculations/aggregates where possible. The first human decision expects no predecessor; successors expect the latest human decision ID. Preserve request-key retry recognition before stale-predecessor validation, current scoped tasks.review authorization, actor attribution, required reasons and self-review exclusions. Competing first decisions serialize; only one succeeds. With no human decision, the explicit decision relation is absent even when effective status is accepted. Use one effective-verdict definition for review reads, receipts, accepted-only queries and export snapshot selection. Keep export capture and stream jobs; no review job is added.

### One sealed import job, existing atomic row transactions

Under the import's seal lock, insert one ProcessImport job with import identity/owning scope if pending rows exist. Job insertion and sealing commit together; retries of sealing add no job. Do not copy row values or an unbounded list of row IDs into job arguments.

The worker reads bounded keyset pages of pending rows, releasing each page before the next. Each row runs its existing process action/transaction and verifies its sealed parent scope. Terminal rows are no-ops. Expected permanent validation failures commit sanitized failed row outcomes and processing continues; transient infrastructure errors roll back the current row and use ordinary Oban retry. Unexpected failures must not fabricate row-validation errors. A retry starts from remaining pending rows, not a stale cursor which could skip uncommitted work. Completed rows and their revisions are not repeated; progress remains derived from native row outcomes. One import job may serialize its own rows initially; do not add chunks or parallel fan-out without implementation benchmarks demonstrating a need.

Retry exhaustion leaves pending progress visible. Automatic terminal-job recovery remains the separate deferred maintenance change, whose repair now targets pending rows under an import job's import identity. Standard Oban uniqueness/retry and per-row locking suffice; no extra progress resource or general batch engine is introduced.

### Keep only useful jobs

Remove unused VerifyAsset and its orphan configuration when no other runtime consumer remains; preserve synchronous verification and all asset authorization/finalization guarantees. Remove ExpireAttempt and ProcessImportRow after replacing their call sites. Keep result-export processing and one import job per nonempty pending sealed import. Reputation separately owns useful Task peer discovery and coalesced worker refresh; native closure, neutral expiry and on-demand diagnostics add no reputation jobs.

## Risks / Trade-offs

- Lazy expiry can leave a physically active overdue row stored → authoritative availability and protected access use deadlines, worker-slot cleanup occurs before issuance, and inspection distinguishes effective expiry without requiring a sweep.
- Narrow locks can expose races if any child-write path bypasses the participation guard → audit every read/save/start and typed-child action and verify concurrency with actual transactions.
- Deriving acceptance can diverge across queries → one effective-verdict definition and focused result/receipt/export checks, including no synthetic predecessor ID.
- One large import can hold a job for longer → bounded reads and short row transactions; benchmark large imports during implementation before considering chunks. A permanently invalid row must not prevent other valid rows.
- Breaking resource/API names affect generated interfaces → update all current callers, schema and development fixtures together; no compatibility aliases.
