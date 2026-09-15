# task-allocation Specification

## Purpose

Issue only actual work to eligible authenticated users while preserving exact input presentation, finite leases, and concurrent submission capacity.

## Requirements

### Requirement: Project-worker eligibility preserves optional membership
Self-service allocation SHALL use the authenticated active global User and explicit active organization/project. An `organization_members` audience SHALL require active membership; `external_users` SHALL require the project's open external-access setting or explicit allow entry without requiring membership; `both` SHALL accept either route. Members SHALL also be able to qualify through the external route. An explicit block SHALL override every positive route. Anonymous sessions, inactive accounts/organizations/projects, and unmatched audiences SHALL fail closed. No separate worker identity, paid offer, or organization-management capability SHALL be inferred.

#### Scenario: An external user claims work without joining
- **WHEN** an active non-member requests work from an active project that permits open external access
- **THEN** they can receive an attempt while remaining a non-member with no general project/dataset/form/asset browsing authority

#### Scenario: Blocks override both routes
- **WHEN** an active member also qualifies through an open external route but has a project block
- **THEN** allocation and live work-bundle access are denied

#### Scenario: One route is revoked while another remains
- **WHEN** membership ends for a worker who still qualifies through the project's external route
- **THEN** the worker remains eligible through that route unless explicitly blocked

### Requirement: Pool claims and direct assignments share one contract
Pool fetch SHALL create claimed attempts; direct assignment SHALL require `tasks.assign` under organization-management checks and create assigned attempts for a specified eligible User. Both SHALL enforce identical project, capacity, lease, provenance, and one-live-attempt-per-project/worker constraints. Owners SHALL be able to start or release their own live attempts under current worker authorization; cancelling another worker's live attempt SHALL require organization-scoped `tasks.assign` and SHALL not return that worker's work bundle. A worker who has attempted a task in any state SHALL not receive it again through ordinary allocation. No linked follow-up or same-task exclusion bypass SHALL be exposed. Start, release, and cancel SHALL use native Ash update actions and record-based domain interfaces. GraphQL SHALL use native result/errors mutations with explicit organization/project/attempt lookups restricted to eligible owners or assignment managers; the transition SHALL recheck operation-specific authority under the owner locks.

#### Scenario: Assignment cannot bypass worker eligibility
- **WHEN** a manager assigns work to a blocked or otherwise ineligible user
- **THEN** no attempt is created even though the manager has assignment permission

#### Scenario: Two requests race for one worker
- **WHEN** different allocation requests concurrently target the same project and worker
- **THEN** at most one live attempt is issued and expired prior leases cannot permanently occupy that slot

### Requirement: Select at fetch time and persist exact issued inputs
Allocation SHALL first prefer an already-issued task with available submission capacity and no prior attempt by that worker. Otherwise it SHALL select the next unissued authored Task by position. It SHALL create only the Attempt and its input presentation, reusing the immutable TaskInputs authored before activation. Task SHALL own canonical membership uniqueness, independent of display order. No group-to-task copying or consumption record SHALL exist. Answers SHALL use TaskInput IDs rather than display labels.

#### Scenario: Activation issues no work
- **WHEN** a project is activated but no worker has fetched work
- **THEN** its authored tasks and inputs exist, but there are no attempts, presentations, or worker/result access to unissued work

#### Scenario: Concurrent selectors choose the same group
- **WHEN** two allocation requests select an equivalent canonical group
- **THEN** both requests refer to the same authored Task, each committed attempt respects capacity, and a failed allocation leaves its task unissued with no attempt or presentation

#### Scenario: Presentation shuffling retains meaning
- **WHEN** two attempts display the same inputs in different orders
- **THEN** each order is persisted, while both answers still identify the same stable TaskInputs

#### Scenario: Explicit groups retain authored order without shuffling
- **WHEN** an authored task is issued with slot shuffling disabled, including a later attempt on the same task
- **THEN** its inputs follow the frozen TaskInput positions within each slot, independent of generated TaskInput IDs

### Requirement: Question capacity is reserved atomically
Every attempt SHALL cover all questions in the pinned published form. Each task SHALL use its frozen project's submission target. Native counts of submitted attempts and physically live attempts SHALL determine remaining capacity under the Task lock; no per-question reservations or progress counters SHALL be persisted. Before checking capacity, allocation SHALL atomically bulk-expire every overdue live attempt on that task using one post-lock database wall-clock cutoff. Those expirations SHALL commit even when the caller receives a successful no-work response. Concurrent issuance SHALL never exceed the target after accounting for submitted and live attempts. A valid submission SHALL count once, including an allowed all-skipped submission. Review decisions and corrections SHALL never change allocation demand. Release, expiry, and cancellation SHALL free live capacity without altering submitted evidence.

#### Scenario: Two workers compete for the last submission
- **WHEN** two fetches compete for a task's last available unit
- **THEN** at most one new attempt is issued

#### Scenario: Expiry cleanup is delayed
- **WHEN** an otherwise full task contains an overdue attempt whose job has not run
- **THEN** allocation expires it under the task lock before considering replacement work

#### Scenario: Review rejects a submitted answer
- **WHEN** an answer is rejected or its acceptance corrected
- **THEN** the original submission still counts toward the task target and no replacement demand is created

### Requirement: No-work outcomes distinguish contention from exhaustion
Allocation SHALL return typed outcomes for `retry_later`, `waiting_for_answers`, `no_work_for_worker`. An interrupted search or locked candidate SHALL not prove global exhaustion. Contention or an existing operation timeout that prevents a definitive conclusion SHALL return a retryable outcome; allocation SHALL impose no fixed candidate-count ceiling on per-request group search. A worker exhausting their own eligible tasks SHALL not close otherwise usable project work. No-work outcomes SHALL disclose no unallocated input content.

#### Scenario: A candidate is temporarily locked
- **WHEN** another transaction prevents a selector from inspecting otherwise possible work
- **THEN** it returns a retryable result rather than completing the project or claiming all submissions are collected

### Requirement: Leases and allocation retries are durable
Attempts SHALL transition from claimed/assigned to in-progress on start or first save, and from a live state to submitted, expired, released, or cancelled. Terminal attempts SHALL never revive. Lease deadlines SHALL use server time, remain fixed after issuance, and be enforced after lock waits whether cleanup has run or not. Every fetch and assignment SHALL require a caller-supplied UUID request key. Invalid UUID input SHALL fail normal argument validation before selecting work or persisting collection changes. A successful allocation SHALL durably associate the validated request key with project, requesting actor, operation, and worker. An identical retry SHALL return the same attempt's current authorized result without a new lease; changed arguments with the same key SHALL conflict. A no-allocation result SHALL not be required to consume a key.

#### Scenario: A response is lost after allocation commits
- **WHEN** the caller retries the same allocation key and arguments
- **THEN** it receives the original attempt without creating another or extending its deadline

#### Scenario: Expiration cleanup is delayed
- **WHEN** an attempt deadline has passed but its expiration job has not run
- **THEN** work reads/saves/submission are denied and candidate-task allocation records its expiry and frees its live capacity before deciding whether to issue another attempt

### Requirement: Attempt ownership bounds worker presentation
GraphQL and domain work-bundle reads SHALL use the same native Ash read action with authorization fields selected independently of requested output fields. Work-bundle reads SHALL require an active eligible owning account, active organization, active/paused project, live attempt, and an unexpired lease. Bundles SHALL expose the pinned form including all published questions, project-wide skip/reason settings, stored input presentation order, typed draft outcomes, and exact bound values from allocated revisions. Optional absence SHALL be explicit. Workers SHALL have no arbitrary task/cohort discovery or reverse traversal into organization data. Terminal worker access SHALL be limited to an owned receipt containing state, timestamps, and accepted/pending/rejected/skipped outcome totals; no answer payloads or source access SHALL be restored. Receipt access SHALL require current account/organization/audience eligibility but no live lease. All nested collections SHALL use bounded Relay keyset pagination, default 50/max 100.

#### Scenario: A worker reads skip settings
- **WHEN** an eligible owner loads their work bundle without project-management permissions
- **THEN** the bundle provides the same frozen skip_allowed and reason_required settings for every question

#### Scenario: A worker substitutes another task
- **WHEN** an owner requests a foreign attempt or unbound source value
- **THEN** the request fails without revealing that record

#### Scenario: Access is revoked
- **WHEN** the worker becomes blocked or loses all audience routes
- **THEN** work reads, writes, receipt reads, and new source access fail

### Requirement: Authored groups are consumed in order
Allocation SHALL lock only the next unissued authored Task when already-issued tasks offer no capacity. It SHALL not skip an earlier locked unissued task or lock unrelated later tasks. Attempt issuance and presentation creation SHALL commit together. A failed transaction SHALL leave the task available for its first issuance. Task capacity SHALL use FOR NO KEY UPDATE locks, preserving exclusive capacity coordination while allowing foreign-key checks from independent review inserts.

#### Scenario: The next group is locked
- **WHEN** another transaction holds the earliest unissued group's lock
- **THEN** allocation returns retry_later without issuing a later task

#### Scenario: A later group is locked
- **WHEN** only a later authored group is locked
- **THEN** the earlier group can still be issued
