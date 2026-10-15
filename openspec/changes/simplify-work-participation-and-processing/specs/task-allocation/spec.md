## MODIFIED Requirements

### Requirement: Pool claims and direct assignments share one contract
Pool fetch SHALL create active TaskParticipations; direct assignment SHALL require `tasks.assign` under organization-management checks and create active TaskParticipations for a specified eligible User. The operation SHALL retain whether issuance was fetch or assignment; a nullable started_at SHALL distinguish deliberate start without separate claimed, assigned or in-progress states. Self-service work SHALL require no separate claim or start confirmation, and first save SHALL start participation implicitly. Both SHALL enforce identical project, capacity, lease, provenance, and one-live-participation-per-project/worker constraints. Owners SHALL be able to start or release their own live participations under current worker authorization; cancelling another worker's live participation SHALL require organization-scoped `tasks.assign` and SHALL not return that worker's work bundle. A worker who has participated in a Task in any state SHALL not receive it again through ordinary allocation. No linked follow-up or same-task exclusion bypass SHALL be exposed. Start, release, and cancel SHALL use native Ash update actions and record-based domain interfaces. GraphQL SHALL use native result/errors mutations with explicit organization/project/participation lookups restricted to eligible owners or assignment managers; the transition SHALL recheck operation-specific authority under the owner locks.

#### Scenario: Assignment cannot bypass worker eligibility
- **WHEN** a manager assigns work to a blocked or otherwise ineligible user
- **THEN** no participation is created even though the manager has assignment permission

#### Scenario: Two requests race for one worker
- **WHEN** different allocation requests concurrently target the same project and worker
- **THEN** at most one live participation is issued and expired prior leases cannot permanently occupy that slot

### Requirement: Question capacity is reserved atomically
Every participation SHALL cover all questions in the pinned published form. Each task SHALL use its frozen project's submission target. Native counts of submitted participations and active participations whose fixed deadlines remain in the future SHALL determine remaining capacity under the Task lock; no per-question reservations or progress counters SHALL be persisted. Allocation SHALL use one post-lock database wall-clock cutoff and atomically record overdue active participations as expired on the selected Task before issuance. Those expirations SHALL commit even when the caller receives a successful no-work response. Concurrent issuance SHALL never exceed the target after accounting for submitted and live participations. A valid submission SHALL count once, including an allowed all-skipped submission. Review decisions and corrections SHALL never change allocation demand. Release, expiry, and cancellation SHALL free live capacity without altering submitted evidence.

#### Scenario: Two workers compete for the last submission
- **WHEN** two fetches compete for a task's last available unit
- **THEN** at most one new participation is issued

#### Scenario: Expiry cleanup is delayed
- **WHEN** an otherwise full task contains an overdue participation whose expiry has not yet been recorded
- **THEN** allocation expires it under the task lock before considering replacement work

#### Scenario: Review rejects a submitted answer
- **WHEN** an answer is rejected or its acceptance corrected
- **THEN** the original submission still counts toward the task target and no replacement demand is created

### Requirement: Leases and allocation retries are durable
TaskParticipations SHALL use states active, submitted, returned, expired and cancelled. Start or first save SHALL set started_at without changing active state; only a deliberate worker action SHALL establish start for a direct assignment. A live participation SHALL mean active with an unexpired fixed deadline. Terminal participations SHALL never revive. The database deadline SHALL remain authoritative without a per-participation expiration job, a separate Lease entity or an in-memory reservation service. Deadline expiry alone SHALL NOT establish worker fault or a reputation failure. Lease deadlines SHALL use server time, remain fixed after issuance, and be enforced after lock waits whether cleanup has run or not. Every fetch and assignment SHALL require a caller-supplied UUID request key. Invalid UUID input SHALL fail normal argument validation before selecting work or persisting collection changes. A successful allocation SHALL durably associate the validated request key with project, requesting actor, operation, and worker. An identical retry SHALL return the same participation's current authorized result without a new lease; changed arguments with the same key SHALL conflict. A no-allocation result SHALL not be required to consume a key.

#### Scenario: A response is lost after allocation commits
- **WHEN** the caller retries the same allocation key and arguments
- **THEN** it receives the original participation without creating another or extending its deadline

#### Scenario: Expiration cleanup is delayed
- **WHEN** a participation deadline has passed but its expired state has not yet been recorded
- **THEN** work reads/saves/submission are denied and candidate-task allocation records its expiry and frees its live capacity before deciding whether to issue another participation

### Requirement: Attempt ownership bounds worker presentation
GraphQL and domain work-bundle reads SHALL use the same native Ash read action with authorization fields selected independently of requested output fields. Work-bundle reads SHALL require an active eligible owning account, active organization, active/paused project, live participation, and an unexpired lease. They SHALL acquire Project protection and the owning participation lock before reading the bundle, retain those locks through the read, and check ownership, live state, and lease expiry after lock waits. Bundles SHALL expose the pinned form including all published questions, project-wide skip/reason settings, stored input presentation order, typed draft outcomes, and exact bound values from allocated revisions. Optional absence SHALL be explicit. Workers SHALL have no arbitrary task/cohort discovery or reverse traversal into organization data. Terminal worker access SHALL be limited to an owned receipt containing state, timestamps, and accepted/pending/rejected/skipped outcome totals; no answer payloads or source access SHALL be restored. Receipt access SHALL require current account/organization/audience eligibility but no live lease. Receipt totals SHALL use native Ash aggregates over outcomes and their effective verdicts, including the frozen automatic default without loading answer payloads. All nested collections SHALL use bounded Relay keyset pagination, default 50/max 100.

#### Scenario: A worker reads skip settings
- **WHEN** an eligible owner loads their work bundle without project-management permissions
- **THEN** the bundle provides the same frozen skip_allowed and reason_required settings for every question

#### Scenario: A worker substitutes another task
- **WHEN** an owner requests a foreign participation or unbound source value
- **THEN** the request fails without revealing that record

#### Scenario: Access is revoked
- **WHEN** the worker becomes blocked or loses all audience routes
- **THEN** work reads, writes, receipt reads, and new source access fail

## ADDED Requirements

### Requirement: Reservations belong to one Task response slot
One TaskParticipation SHALL reserve one response slot for one shared Task and cover every question in its pinned form. A Project SHALL group many independently completable Tasks; allocation SHALL NOT reserve the whole Project or create separate question reservations. The existing maximum of one active participation per worker per Project SHALL remain an independent concurrency limit. A worker SHALL be able to complete any number of distinct available Tasks, subject to ordinary authorization, capacity and admission checks, without an obligation to complete the entire Project. Reservations SHALL be durable and have a fixed server deadline appropriate to the configured work duration; client caching SHALL NOT grant capacity or extend that deadline. Unissued work SHALL remain inaccessible.

#### Scenario: A worker completes a few image Tasks
- **WHEN** a Project contains one thousand image Tasks, each with the same small pinned form and a target of three submissions
- **THEN** each participation reserves one of three slots on one image Task, and that worker may stop after ten Tasks while other eligible workers fill remaining slots

#### Scenario: A participation contains several questions
- **WHEN** a Task offers one image and three required questions
- **THEN** its reservation covers the whole Task and submission requires an explicit valid answer or allowed skip for every question, rather than three independent reservations
