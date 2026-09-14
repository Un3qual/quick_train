## MODIFIED Requirements

### Requirement: Progress is rebuildable from authoritative evidence
Question progress SHALL persist accepted, pending, skipped, rejected, live-reservation, and failure counts. Attention and Task state SHALL be Ash calculations over those counters, frozen thresholds, and project state, without separately stored status fields or status synchronization writes. Accumulated progress and failure counts SHALL use integer storage and arithmetic that support values beyond signed 32-bit range, and SHALL serialize through GraphQL String as canonical nonnegative base-10 integers (zero as `"0"`, no sign, leading zeros, fraction, or exponent). Counts SHALL remain exact without clamping to a target or narrowing to GraphQL Int; configured targets and thresholds SHALL retain signed 32-bit Int bounds. Effective decisions, submitted outcomes, and attempts SHALL be authoritative; projections SHALL be rebuildable without changing them. Submission, review/correction, release, expiry, cancellation, and allocation SHALL update affected progress consistently with their committed evidence. Reconciliation concurrent with an evidence change SHALL not overwrite newer state using a stale read. Task state SHALL be derived in this precedence order after every evidence change: satisfied when all question targets are met; otherwise cancelled when its project is completed or archived; otherwise needs_attention when all remaining unmet questions are escalated; otherwise open. Corrections in closed projects SHALL therefore move task projections between satisfied and cancelled as their targets change, never to open or needs_attention. They SHALL not revive terminal attempts or authorize collection, regardless of the new task state.

#### Scenario: A rejected answer opens demand
- **WHEN** the current effective decision changes an answer from accepted/pending to rejected on an active project
- **THEN** its question capacity is recalculated and additional eligible work can be offered unless escalation prevents it

#### Scenario: A correction raises accepted progress beyond GraphQL Int
- **WHEN** a question has an accepted target and accepted count of 2,147,483,647 and an earlier rejected answer is corrected to accepted
- **THEN** its accepted count becomes 2,147,483,648 and GraphQL returns `"2147483648"`, preserving every accepted answer and satisfied state without reopening capacity

#### Scenario: Reconciliation overlaps submission
- **WHEN** progress rebuilding races a successful submission
- **THEN** final progress includes that committed evidence exactly once

#### Scenario: A closed task loses satisfaction
- **WHEN** a correction in a completed or archived project rejects an acceptance needed to satisfy a previously satisfied task
- **THEN** its progress becomes unmet and its state becomes cancelled without reopening collection or changing terminal attempt states

#### Scenario: A cancelled task becomes satisfied after correction
- **WHEN** a correction in a completed or archived project makes every target of a cancelled task satisfied
- **THEN** its state becomes satisfied and the corrected evidence remains visible, while the project stays closed and no attempt revives

### Requirement: Follow-up work creates linked new evidence
Follow-up assignment SHALL require an active account, active owning organization, active membership, and both `tasks.assign` and `tasks.results.read` in the same organization/project scope. The existing paginated audit task/attempt relationships SHALL make terminal predecessor IDs discoverable. An authorized manager SHALL be able to deliberately issue a new attempt linked to a selected terminal predecessor of that task for an explicitly selected eligible worker, who MAY be the predecessor's worker or another worker. The predecessor SHALL belong to the same task/project and SHALL provide evidence lineage, not constrain worker identity. Follow-up creation and retries SHALL recheck both capabilities; an assign-only or results-only caller SHALL be denied. Ordinary direct assignment SHALL continue to require only `tasks.assign`; no assignment-specific discovery API or implicit result-read grant SHALL be introduced. The operation SHALL bypass ordinary same-task exclusion and escalation only for unmet questions. It SHALL still enforce the selected worker's current eligibility, active project, one-live-attempt limit, capacity, and a fresh fixed lease. Both predecessor and selected worker SHALL participate in the existing allocation request identity. It SHALL not reset historical failures or mutate the old response. No fulfilled question SHALL be reopened merely to collect extra answers.

#### Scenario: A manager discovers a pool attempt for follow-up
- **WHEN** a manager with both capabilities inspects audit task/attempt connections after pool-claimed attempts have caused escalation
- **THEN** the terminal predecessor IDs are discoverable through those existing reads, and the manager can select one to create a linked follow-up without receiving an ID out of band

#### Scenario: Follow-up authority is incomplete
- **WHEN** a caller lacks either `tasks.assign` or `tasks.results.read`, even if it knows a valid predecessor ID or is retrying a prior follow-up
- **THEN** follow-up assignment fails without issuing work; ordinary direct assignment remains available to an otherwise authorized assign-only manager

#### Scenario: A skipped question is deliberately reassigned
- **WHEN** a manager assigns a follow-up to the worker of a terminal skipped attempt and the question still has capacity
- **THEN** a new linked attempt owning its own draft revision and outcomes is created while the prior skip stays queryable

#### Scenario: A follow-up targets a blocked worker
- **WHEN** the selected worker no longer meets the project's audience rules
- **THEN** assignment fails despite the deliberate follow-up request

#### Scenario: Prior workers cannot resolve an escalated question
- **WHEN** an unmet question is escalated and every worker on its prior terminal attempts is now ineligible
- **THEN** a manager can link a follow-up to a prior terminal attempt and assign another currently eligible worker, retaining the old evidence and failure history without reopening ordinary circulation

#### Scenario: A follow-up retry changes its worker
- **WHEN** a manager reuses an allocation request key and predecessor with a different selected worker
- **THEN** the request conflicts rather than silently retargeting the recorded follow-up or creating another attempt
