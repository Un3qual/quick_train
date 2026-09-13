## Purpose

Review individual submitted question outcomes without rewriting worker evidence, and derive explainable task progress and escalation from that evidence.

## ADDED Requirements

### Requirement: Automatic and manual per-question review
For a project frozen in `automatic` review mode, successful submission SHALL atomically append a system-origin acceptance for each answered outcome. For a project frozen in `manual` review mode, submission SHALL append no review decision and SHALL leave answered outcomes pending until an active account with active membership in the active owning organization and `tasks.review` appends an accept/reject decision under explicit organization/project scope. Submitted skips SHALL be non-reviewable: accept, reject, and correction actions SHALL reject them without appending a decision. A whole-response batch containing a skip SHALL fail atomically without appending any decisions. Every manual decision, correction, and whole-response review SHALL recheck the active account, active owning organization, active membership, and `tasks.review` under explicit organization/project scope. Reviewers SHALL not edit worker answers or manually review their own responses. Rejections SHALL require a nonblank reason. Whole-response review SHALL persist per-question decisions with atomic all-or-nothing validation and no additional batch-size ceiling. Review and correction reasons SHALL have no task-specific byte ceiling; nonblank-reason requirements and existing request handling SHALL remain in force.

#### Scenario: An answered outcome is submitted in manual mode
- **WHEN** a worker successfully submits an answered outcome to a manual-review project
- **THEN** it remains pending with no system acceptance and reserves capacity until a reviewer decides

#### Scenario: A response receives mixed decisions
- **WHEN** a reviewer accepts one submitted answer and rejects another
- **THEN** each question has its own attributable decision and the worker's immutable response stays unchanged

#### Scenario: A reviewer attempts self-review
- **WHEN** a user with review permission targets their own submitted response
- **THEN** the manual decision is denied

#### Scenario: A review request targets a submitted skip
- **WHEN** an authorized reviewer targets a submitted skip with an individual decision, correction, or whole-response batch that also selects an answered outcome
- **THEN** the request fails without appending any decision, the submitted evidence remains unchanged, and the skip still contributes exactly one failure

#### Scenario: The owning organization is inactive
- **WHEN** an active reviewer with active membership requests a decision, correction, or whole-response review for an inactive organization
- **THEN** the request is denied without appending decisions or changing evidence or progress

### Requirement: Corrections are append-only and conflict-aware
Each QuestionResponse's review history SHALL be immutable and ordered. A decision SHALL identify its actor/system origin, verdict, creation time, and predecessor. The latest decision SHALL determine the effective verdict. A correction SHALL require a nonblank reason and expected current decision identity; a stale expectation SHALL conflict without changing history. Each manual decision or correction SHALL require a caller-supplied UUID request key, validated before persistence; any invalid UUID in a whole-response batch SHALL reject the entire batch without appending decisions. A decision request key scoped to QuestionResponse and requesting actor SHALL converge identical retries and reject different content under the same key for that outcome. Another QuestionResponse SHALL have an independent key scope even when it answers the same form question. Corrections SHALL remain permitted in completed/archived projects but SHALL not reopen collection there. Accepted evidence above the configured target SHALL remain visible.

#### Scenario: One reviewer reuses a key across responses
- **WHEN** a reviewer uses the same request key for two different QuestionResponses answering the same form question
- **THEN** each authorized decision is recorded independently, an identical retry for either outcome returns its own decision, and different content under that outcome's existing key conflicts

#### Scenario: Two reviewers race
- **WHEN** two decisions name the same current predecessor
- **THEN** one succeeds and the other conflicts; history never acquires two competing effective successors

#### Scenario: Acceptance is corrected after closure
- **WHEN** an authorized reviewer rejects an earlier accepted answer in a completed project with a valid predecessor and reason
- **THEN** a successor decision changes current results and progress while the previous decision/submission remain intact and no new work is issued

### Requirement: Progress is rebuildable from authoritative evidence
Question progress SHALL expose accepted, pending, skipped, rejected, and live-reservation counts and attention state. Accumulated progress and failure counts SHALL use integer storage and arithmetic that support values beyond signed 32-bit range, and SHALL serialize through GraphQL String as canonical nonnegative base-10 integers (zero as `"0"`, no sign, leading zeros, fraction, or exponent). Counts SHALL remain exact without clamping to a target or narrowing to GraphQL Int; configured targets and thresholds SHALL retain signed 32-bit Int bounds. Effective decisions, submitted outcomes, and attempts SHALL be authoritative; projections SHALL be rebuildable without changing them. Submission, review/correction, release, expiry, cancellation, and allocation SHALL update affected progress consistently with their committed evidence. Reconciliation concurrent with an evidence change SHALL not overwrite newer state using a stale read. Task state SHALL be derived in this precedence order after every evidence change: satisfied when all question targets are met; otherwise cancelled when its project is completed or archived; otherwise needs_attention when all remaining unmet questions are escalated; otherwise open. Corrections in closed projects SHALL therefore move task projections between satisfied and cancelled as their targets change, never to open or needs_attention. They SHALL not revive terminal attempts or authorize collection, regardless of the new task state.

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

### Requirement: Repeated failures stop automatic circulation
For an unsatisfied question, cumulative submitted skips plus currently rejected answered outcomes plus expired/released attempts that offered it SHALL count toward its positive frozen failure threshold, default 5. Deliberate cancellation SHALL not count as a worker failure. Attention SHALL be derived after every evidence change and during reconciliation: it SHALL apply exactly when the accepted target is unmet and the current failure count is at or above the threshold. A question requiring attention SHALL stop receiving ordinary new reservations; already-issued valid attempts SHALL remain submittable. A correction that reduces failures below the threshold SHALL clear attention even if the target remains unmet, permitting ordinary allocation only subject to the existing active-project, worker-eligibility, same-task exclusion, and capacity rules. Other unblocked questions SHALL remain eligible. Meeting the accepted target SHALL satisfy the question and clear attention without erasing its skip/rejection history.

#### Scenario: Repeated skips escalate one question
- **WHEN** a question reaches its failure threshold through submitted skips while another question remains answerable
- **THEN** future ordinary attempts omit the escalated question and can still offer the other question

#### Scenario: A correction clears attention before satisfying the target
- **WHEN** an active project question has five rejected outcomes, no other failures, and threshold 5, and one rejection is corrected to accepted while its accepted target remains unmet
- **THEN** its failure count becomes four and attention clears, both immediately and on reconciliation, allowing ordinary allocation to an otherwise eligible new worker when capacity is available while retaining review history

### Requirement: Follow-up work creates linked new evidence
An active organization member with `tasks.assign` SHALL be able to deliberately issue a new attempt linked to a previous terminal attempt of that task for an explicitly selected eligible worker, who MAY be the predecessor's worker or another worker. The predecessor SHALL belong to the same task/project and SHALL provide evidence lineage, not constrain worker identity. The operation SHALL bypass ordinary same-task exclusion and escalation only for unmet questions. It SHALL still enforce the selected worker's current eligibility, active project, one-live-attempt limit, capacity, and a fresh fixed lease. Both predecessor and selected worker SHALL participate in the existing allocation request identity. It SHALL not reset historical failures or mutate the old response. No fulfilled question SHALL be reopened merely to collect extra answers.

#### Scenario: A skipped question is deliberately reassigned
- **WHEN** a manager assigns a follow-up to the worker of a terminal skipped attempt and the question still has capacity
- **THEN** a new linked attempt/response is created while the prior skip stays queryable

#### Scenario: A follow-up targets a blocked worker
- **WHEN** the selected worker no longer meets the project's audience rules
- **THEN** assignment fails despite the deliberate follow-up request

#### Scenario: Prior workers cannot resolve an escalated question
- **WHEN** an unmet question is escalated and every worker on its prior terminal attempts is now ineligible
- **THEN** a manager can link a follow-up to a prior terminal attempt and assign another currently eligible worker, retaining the old evidence and failure history without reopening ordinary circulation

#### Scenario: A follow-up retry changes its worker
- **WHEN** a manager reuses an allocation request key and predecessor with a different selected worker
- **THEN** the request conflicts rather than silently retargeting the recorded follow-up or creating another attempt
