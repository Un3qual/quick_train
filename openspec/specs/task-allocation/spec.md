# task-allocation Specification

## Purpose

Issue only actual work to eligible authenticated users while preserving exact input presentation, finite leases, coverage, and concurrent answer capacity.

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
Pool fetch SHALL create claimed attempts; direct assignment SHALL require `tasks.assign` under organization-management checks and create assigned attempts for a specified eligible User. Both SHALL enforce identical project, capacity, lease, provenance, and one-live-attempt-per-project/worker constraints. Owners SHALL be able to start or release their own live attempts under current worker authorization; cancelling another worker's live attempt SHALL require organization-scoped `tasks.assign` and SHALL not return that worker's work bundle. A worker who has attempted a task in any state SHALL not receive it again through ordinary allocation. Only the explicit linked follow-up operation SHALL bypass that exclusion; it SHALL additionally require `tasks.results.read`, with terminal predecessor IDs discoverable through the existing audit relationships.

#### Scenario: Assignment cannot bypass worker eligibility
- **WHEN** a manager assigns work to a blocked or otherwise ineligible user
- **THEN** no attempt is created even though the manager has assignment permission

#### Scenario: Two requests race for one worker
- **WHEN** different allocation requests concurrently target the same project and worker
- **THEN** at most one live attempt is issued and expired prior leases cannot permanently occupy that slot

### Requirement: Select at fetch time and persist exact issued inputs
Allocation SHALL first prefer an existing non-escalated task with available question capacity and no prior attempt by that worker. Otherwise it SHALL select a balanced group or consume the next eligible explicit group, create one Task and its exact immutable TaskInputs, and record per-attempt display positions. The canonical group SHALL be unique within its project, independent of shuffled display order. New tasks SHALL exist only when an attempt is actually issued. Inputs SHALL reference exact enrolled revisions and slots; answers SHALL use TaskInput IDs rather than display labels.

#### Scenario: An unused pair is never materialized
- **WHEN** a balanced project is activated but no worker has fetched work
- **THEN** it contains no generated Tasks or random pair schedule

#### Scenario: Concurrent selectors choose the same group
- **WHEN** two allocation requests select an equivalent canonical group
- **THEN** at most one Task exists for it, each committed attempt respects capacity, and a failed allocation leaves no orphan issued group or consumed explicit entry

#### Scenario: Presentation shuffling retains meaning
- **WHEN** two attempts display the same inputs in different orders
- **THEN** each order is persisted, while both answers still identify the same stable TaskInputs

### Requirement: Question capacity is reserved atomically
Each task question SHALL track its accepted target separately. Available capacity SHALL exclude effectively accepted answers, pending submitted answers, and unexpired live reservations. Before checking capacity and escalation on an existing candidate task, allocation SHALL expire all physically live attempts on that task whose deadlines are at or before a database wall-clock cutoff taken after locking its task/progress rows, regardless of worker. In the same transaction it SHALL update their offered-question reservations, expiry failure contributions, derived attention, and task state exactly once. These updates SHALL remain committed on a successful no-work result, and later cleanup SHALL not count the failures again. Allocation SHALL atomically reserve one unit for each currently available non-escalated question and persist exactly that offered question set on the attempt. At least one question SHALL be offered. Skips, rejections, expiration, release, and cancellation SHALL release capacity as applicable; submitted answered outcomes SHALL replace live reservations with pending/accepted evidence. Concurrent operations SHALL never exceed capacity when issuing attempts. Later review corrections SHALL preserve all accepted evidence even when it exceeds the target.

#### Scenario: Another worker's overdue attempt reaches the failure threshold
- **WHEN** worker B fetches a task with an unmet question at four failures and threshold five while worker A's offered attempt is overdue but its cleanup job has not run
- **THEN** allocation expires A's attempt and records the fifth failure before selecting questions, omits that escalated question from B's ordinary reservation, and preserves the expiry update even if no work is issued; later cleanup leaves the count at five

#### Scenario: Two workers compete for the last answer
- **WHEN** two fetches compete for one remaining unit on a question
- **THEN** only one reserves that unit

#### Scenario: A later attempt has fewer questions
- **WHEN** one task question is already satisfied and another still has capacity
- **THEN** a new attempt offers only the latter question and its presentation marks which question placements require responses

#### Scenario: Manual review keeps capacity occupied
- **WHEN** the available answer has been submitted and is pending review
- **THEN** another attempt is not issued for that reserved target until review or correction opens capacity

### Requirement: Coverage measures issued groups independently of answers
Coverage SHALL count an item's appearances across distinct issued tasks, including tasks later cancelled, independently of per-question answer counts. Existing-task replication and follow-ups SHALL not increase item coverage. Balanced selection SHALL prioritize under-covered items and least-exposed compatible companions; coverage targets SHALL be lower goals rather than hard upper bounds because companions may exceed their own goals while another item remains under-covered. Once every item's coverage goal is met, balanced mode SHALL create no further groups but SHALL continue eligible existing-task work. Answer targets SHALL belong to an exact task/question; answers to a new group SHALL not fulfill another group's demand. Explicit mode SHALL issue authored groups by position with atomic consumption. Only `balanced` and `explicit` SHALL be accepted.

#### Scenario: Replication does not invent coverage
- **WHEN** three workers answer the same issued pair
- **THEN** each underlying item has one group exposure while question progress contains three attributable answers

#### Scenario: A straggling item needs a companion
- **WHEN** an under-covered item can only form a valid group with an item already at its coverage target
- **THEN** balanced selection can issue the group and count the companion's additional exposure

#### Scenario: Covered items still need answers on existing tasks
- **WHEN** every item meets its coverage goal and a worker has attempted all remaining unsatisfied tasks
- **THEN** ordinary allocation returns `no_work_for_worker` without creating different groups or closing the project; other eligible workers or deliberate linked follow-ups can fill the existing task targets

### Requirement: No-work outcomes distinguish contention from exhaustion
Allocation SHALL return typed outcomes for `retry_later`, `waiting_for_answers`, `no_work_for_worker`, and `needs_attention`. An interrupted search or locked candidate SHALL not prove global exhaustion. Contention or an existing operation timeout that prevents a definitive conclusion SHALL return a retryable outcome; allocation SHALL impose no fixed candidate-count ceiling on per-request group search. A worker exhausting their own eligible tasks SHALL not close or escalate otherwise usable project work. No-work outcomes SHALL disclose no unallocated input content.

#### Scenario: A candidate is temporarily locked
- **WHEN** another transaction prevents a selector from inspecting otherwise possible work
- **THEN** it returns a retryable result rather than completing the project or marking coverage satisfied

### Requirement: Leases and allocation retries are durable
Attempts SHALL transition from claimed/assigned to in-progress on start or first save, and from a live state to submitted, expired, released, or cancelled. Terminal attempts SHALL never revive. Lease deadlines SHALL use server time, remain fixed after issuance, and be enforced after lock waits whether cleanup has run or not. Every fetch, assignment, and follow-up allocation SHALL require a caller-supplied UUID request key. Invalid UUID input SHALL fail normal argument validation before selecting work or persisting collection changes. A successful allocation SHALL durably associate the validated request key with project, requesting actor, operation, worker, and follow-up target when present. An identical retry SHALL return the same attempt's current authorized result without a new lease; changed arguments with the same key SHALL conflict. A no-allocation result SHALL not be required to consume a key.

#### Scenario: A response is lost after allocation commits
- **WHEN** the caller retries the same allocation key and arguments
- **THEN** it receives the original attempt without creating another or extending its deadline

#### Scenario: Expiration cleanup is delayed
- **WHEN** an attempt deadline has passed but its expiration job has not run
- **THEN** work reads/saves/submission are denied and candidate-task allocation records its expiry, released reservation, and failure/attention effect before deciding whether to issue another attempt

### Requirement: Attempt ownership bounds worker presentation
A work bundle SHALL require current ownership, an unexpired live attempt, an active account/organization, a matching audience route without a block, and an active or paused project. It SHALL expose only the pinned published form contract, offered questions with their frozen `skip_allowed` and `reason_required` boolean policy values, actual input ordering, and values bound from allocated revisions. These policy fields SHALL describe skipped-outcome rules for each offered question without granting general project/policy access or exposing policies for unoffered questions. Missing optional values SHALL be explicit. Workers SHALL have no arbitrary task/cohort discovery or reverse traversal into organization data. After terminal state, only an owner's receipt of attempt state/timestamps/review status SHALL remain available through worker APIs, requiring active account/organization, ownership, and current unblocked audience eligibility but not a live lease or active project. All work-bundle collections SHALL use bounded Relay keyset pagination, default 50/max 100.

#### Scenario: A worker can determine the skip rules before answering
- **WHEN** an eligible owner fetches a bundle offering questions with different skip/reason policies, without `projects.read` or `projects.manage`
- **THEN** each offered question exposes its frozen `skip_allowed` and `reason_required` values so the client can offer skipping and require a reason as appropriate; unoffered policies and general policy traversal remain unavailable

#### Scenario: A worker substitutes another task ID
- **WHEN** an attempt owner requests an unrelated task, revision, question version, or bound value
- **THEN** the request fails without revealing the unrelated record

#### Scenario: Access is revoked during a lease
- **WHEN** the worker becomes blocked or loses all audience routes
- **THEN** new work reads, saves, submissions, and asset-access issuance fail while prior evidence remains intact
