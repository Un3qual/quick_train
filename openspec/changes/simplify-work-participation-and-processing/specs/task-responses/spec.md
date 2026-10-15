## MODIFIED Requirements

### Requirement: One draft becomes one immutable submission
Each TaskParticipation SHALL own its draft revision and QuestionResponse outcomes directly. Submission SHALL use a native Ash TaskParticipation update with a record-based domain interface and a scoped result/errors GraphQL mutation, retaining validation and the effective review default in the same transaction. It SHALL transition that participation to submitted and freeze its outcomes; no separate Response resource or draft/submitted lifecycle SHALL be persisted. Save SHALL use a native Ash TaskParticipation update with a record-based domain interface and scoped result/errors GraphQL mutation. Answer replacement, revision increment, and implicit start SHALL commit in that one action, without separate revision/start actions. Save SHALL require the current eligible owner and unexpired live participation in an active or paused project. Every draft question outcome/child write or delete SHALL acquire Project protection and the owning participation lock, retaining them through commit. Submission and capacity-changing terminal transitions SHALL instead use Project → Task → participation ordering and retain their locks through commit. After acquiring those locks it SHALL recheck current eligibility, project state, participation ownership/live state, database wall-clock lease deadline, and submission state, serializing with release, expiry, cancellation, project completion, and submission. Saves SHALL replace one complete question outcome atomically, require the current `expected_revision`, and increment that revision; stale revisions SHALL fail without overwriting newer work. Submission SHALL atomically validate all questions of the pinned published form, freeze the response and descendants, transition the participation, and update capacity/review evidence. An authorized submit retry SHALL return the existing submission without duplicating outcomes or explicit reviews. Returned/expired/cancelled drafts SHALL never become submitted.

A single worker's small Task MAY load its question definitions and own draft outcomes together for validation and one atomic submission. It SHALL NOT require question-by-question processing jobs, checkpoints or a resumable submission lifecycle. Existing public pagination, type validation, scoped authority, deadline checks and bounded source/typed-child traversal SHALL remain effective. This SHALL NOT permit loading a complete multi-worker answer population or worker reputation history as part of the bundle. Ordinary post-commit reputation work SHALL retain its separate contract.

#### Scenario: A save races submission
- **WHEN** a question save and submit run concurrently
- **THEN** either the whole save is included in the validated submission or submission wins and the save fails; no descendant changes after freezing

#### Scenario: A stale client saves over newer work
- **WHEN** the supplied participation revision differs from its current revision
- **THEN** the write returns `stale_response` without changing any outcome

#### Scenario: Submission fails on one question
- **WHEN** one offered outcome is missing or invalid
- **THEN** no participation, outcome, or review transition commits and the valid draft remains editable while the lease permits

#### Scenario: A draft save races attempt terminalization
- **WHEN** a draft replacement or child edit/delete races release, expiry, cancellation, or project completion
- **THEN** the save either commits first while its participation remains eligible and live, or observes terminalization after acquiring the required locks and fails without changing the draft

#### Scenario: A small Task submits as one unit
- **WHEN** a worker submits a Task with three answered questions
- **THEN** all offered questions validate and freeze in one atomic submission without per-question processing jobs or intermediate submission states
- **AND** a missing or invalid question still rejects the whole submission without publishing partial results
