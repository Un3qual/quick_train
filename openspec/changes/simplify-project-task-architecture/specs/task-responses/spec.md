## MODIFIED Requirements

### Requirement: One draft becomes one immutable submission
Each Attempt SHALL own its draft revision and QuestionResponse outcomes directly. Submission SHALL transition that Attempt to submitted and freeze its outcomes; no separate Response resource or draft/submitted lifecycle SHALL be persisted. Save SHALL require the current eligible owner and unexpired live attempt in an active or paused project. Every question outcome/child write or delete SHALL acquire the shared Project lock, then Task and Attempt locks in that order and retain them through commit. After acquiring those locks it SHALL recheck current eligibility, project state, attempt ownership/live state, database wall-clock lease deadline, and submission state, serializing with release, expiry, cancellation, project completion, and submission. Saves SHALL replace one complete question outcome atomically, require the current `expected_revision`, and increment that revision; stale revisions SHALL fail without overwriting newer work. Submission SHALL atomically validate all and only offered questions, freeze the response and descendants, transition the attempt, and update capacity/review evidence. An authorized submit retry SHALL return the existing submission without duplicating outcomes or automatic reviews. Released/expired/cancelled drafts SHALL never become submitted.

#### Scenario: A save races submission
- **WHEN** a question save and submit run concurrently
- **THEN** either the whole save is included in the validated submission or submission wins and the save fails; no descendant changes after freezing

#### Scenario: A stale client saves over newer work
- **WHEN** the supplied attempt revision differs from its current revision
- **THEN** the write returns `stale_response` without changing any outcome

#### Scenario: Submission fails on one question
- **WHEN** one offered outcome is missing or invalid
- **THEN** no attempt, outcome, reservation, or review transition commits and the valid draft remains editable while the lease permits

#### Scenario: A draft save races attempt terminalization
- **WHEN** a draft replacement or child edit/delete races release, expiry, cancellation, or project completion
- **THEN** the save either commits first while its attempt remains eligible and live, or observes terminalization after acquiring the required locks and fails without changing the draft

### Requirement: Response writes are explicitly exposed
GraphQL SHALL expose deliberate typed save/submit operations returning Attempt with its revision and paginated typed outcomes. Outcomes SHALL identify their owning attempt; separate Response query roots SHALL not exist. GraphQL SHALL expose paginated typed outcome inspection; generic submitted-outcome/child update and delete mutations SHALL not exist. Responses SHALL satisfy the pinned published form constraints and existing HTTP request behavior. This change SHALL add no separate answer/reason/explanation byte limit, offered-question cap, span-count ceiling, or combined annotation budget. Invalid operations SHALL fail atomically and all collections SHALL follow existing Relay keyset pagination conventions.

#### Scenario: A span answer violates its published contract
- **WHEN** a draft replacement violates the pinned question's published annotation constraint
- **THEN** the whole question write fails without replacing the previous draft answer
