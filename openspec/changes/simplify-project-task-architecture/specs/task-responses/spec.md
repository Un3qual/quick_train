## MODIFIED Requirements

### Requirement: One draft becomes one immutable submission
Each Attempt SHALL own its draft revision and QuestionResponse outcomes directly. Submission SHALL transition that Attempt to submitted and freeze its outcomes; no separate Response resource or draft/submitted lifecycle SHALL be persisted. Save SHALL require the current eligible owner and unexpired live attempt in an active or paused project. Every question outcome/child write or delete SHALL acquire the shared Project lock, then Task and Attempt locks in that order and retain them through commit. After acquiring those locks it SHALL recheck current eligibility, project state, attempt ownership/live state, database wall-clock lease deadline, and submission state, serializing with release, expiry, cancellation, project completion, and submission. Saves SHALL replace one complete question outcome atomically, require the current `expected_revision`, and increment that revision; stale revisions SHALL fail without overwriting newer work. Submission SHALL atomically validate all questions of the pinned published form, freeze the response and descendants, transition the attempt, and update capacity/review evidence. An authorized submit retry SHALL return the existing submission without duplicating outcomes or automatic reviews. Released/expired/cancelled drafts SHALL never become submitted.

#### Scenario: A save races submission
- **WHEN** a question save and submit run concurrently
- **THEN** either the whole save is included in the validated submission or submission wins and the save fails; no descendant changes after freezing

#### Scenario: A stale client saves over newer work
- **WHEN** the supplied attempt revision differs from its current revision
- **THEN** the write returns `stale_response` without changing any outcome

#### Scenario: Submission fails on one question
- **WHEN** one offered outcome is missing or invalid
- **THEN** no attempt, outcome, or review transition commits and the valid draft remains editable while the lease permits

#### Scenario: A draft save races attempt terminalization
- **WHEN** a draft replacement or child edit/delete races release, expiry, cancellation, or project completion
- **THEN** the save either commits first while its attempt remains eligible and live, or observes terminalization after acquiring the required locks and fails without changing the draft

### Requirement: Missing answered and skipped are distinct
Every question in the pinned published form SHALL have exactly one explicit answered or skipped outcome before submission. Questions outside that form SHALL be rejected. A skip SHALL be permitted only by the frozen project-wide skip setting, contain no answer value, and preserve a server timestamp plus a nonblank reason when required. Optional explanations SHALL remain supported. An all-skipped submission SHALL be valid when skipping is enabled and SHALL count once toward the task's submission target. Skips SHALL remain immutable queryable evidence and SHALL not become accepted answers.

#### Scenario: Absence is not a skip
- **WHEN** a worker submits without an outcome for a published question
- **THEN** submission fails rather than inferring an answer or skip

#### Scenario: A draft answer is replaced by a skip
- **WHEN** the project allows skipping and the owner replaces a draft answer
- **THEN** the skip and removal of all previous answer children commit together

#### Scenario: A skip requires a reason
- **WHEN** the project requires a reason and only whitespace is supplied
- **THEN** the write fails without freezing the attempt
