## MODIFIED Requirements

### Requirement: One draft becomes one immutable submission
Each Attempt SHALL own its draft revision and QuestionResponse outcomes directly. Submission SHALL use a native Ash Attempt update with a record-based domain interface and a scoped result/errors GraphQL mutation, retaining validation and automatic decisions in the same transaction. It SHALL transition that Attempt to submitted and freeze its outcomes; no separate Response resource or draft/submitted lifecycle SHALL be persisted. Save SHALL use a native Ash Attempt update with a record-based domain interface and scoped result/errors GraphQL mutation. Answer replacement, revision increment, and implicit start SHALL commit in that one action, without separate revision/start actions. Save SHALL require the current eligible owner and unexpired live attempt in an active or paused project. Every question outcome/child write or delete SHALL acquire the shared Project lock, then Task and Attempt locks in that order and retain them through commit. After acquiring those locks it SHALL recheck current eligibility, project state, attempt ownership/live state, database wall-clock lease deadline, and submission state, serializing with release, expiry, cancellation, project completion, and submission. Saves SHALL replace one complete question outcome atomically, require the current `expected_revision`, and increment that revision; stale revisions SHALL fail without overwriting newer work. Submission SHALL atomically validate all questions of the pinned published form, freeze the response and descendants, transition the attempt, and update capacity/review evidence. An authorized submit retry SHALL return the existing submission without duplicating outcomes or automatic reviews. Released/expired/cancelled drafts SHALL never become submitted.

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
Every question in the pinned published form SHALL have exactly one explicit answered or skipped outcome before submission. Questions outside that form SHALL be rejected. A skip SHALL be permitted only by the frozen project-wide skip setting, contain no answer value, and preserve a server timestamp plus a nonblank reason when required. When `reason_required` is false, omitted, empty, and whitespace-only skip reasons SHALL remain valid and preserve their supplied value. Optional explanations SHALL remain supported. An all-skipped submission SHALL be valid when skipping is enabled and SHALL count once toward the task's submission target. Skips SHALL remain immutable queryable evidence and SHALL not become accepted answers.

#### Scenario: Absence is not a skip
- **WHEN** a worker submits without an outcome for a published question
- **THEN** submission fails rather than inferring an answer or skip

#### Scenario: A draft answer is replaced by a skip
- **WHEN** the project allows skipping and the owner replaces a draft answer
- **THEN** the skip and removal of all previous answer children commit together

#### Scenario: A skip requires a reason
- **WHEN** the project requires a reason and only whitespace is supplied
- **THEN** the write fails without freezing the attempt

### Requirement: Typed answers retain published form semantics
Ash create validations SHALL enforce scalar payload compatibility for ordinary and bulk question-response writes: only answered outcomes may contain scalar values, and each populated scalar field SHALL match the answer family. This rule SHALL live in Elixir rather than a PostgreSQL business-rule check; scoped foreign keys, uniqueness, and simple value bounds SHALL remain database integrity constraints.

Answered outcomes SHALL use exactly their published answer family and matching normalized typed representation, never JSONB answer content. The system SHALL support text, integer, decimal, boolean, static single/multiple choice, task-input single/multiple choice, and complete task-input ranking. Constraints SHALL come from the pinned published question, including the published meanings of absent scalar constraint records. Integers SHALL fit signed 32-bit Int; decimals SHALL preserve precision and reject non-finite values; text SHALL preserve exact valid Unicode content/whitespace and reject NUL. Single choice SHALL select exactly one valid option/input, multiple choice SHALL contain unique selections within bounds, and ranking SHALL be a complete unique ordered permutation of the question's slot inputs. Options SHALL belong to the exact question and TaskInputs to the exact task and referenced slot. Drafts MAY omit scalar values or contain fewer selections, ranking entries, or spans than the published minimum. Saves SHALL enforce local types, ownership, provenance, uniqueness, maximum counts, and valid ranking positions. Submission SHALL additionally require scalar values and minimum counts, including exactly one single-choice selection and a complete ranking.

#### Scenario: A foreign option is supplied
- **WHEN** an answer references an option from a different question or published version
- **THEN** it fails without revealing or persisting the foreign relationship

#### Scenario: A ranking omits an input
- **WHEN** a ranking contains duplicates, missing inputs, or inputs from another slot/task
- **THEN** submission fails rather than storing a partial or ambiguous ranking

#### Scenario: Decimal and text values retain meaning
- **WHEN** a valid answer contains a high-precision decimal or text with significant whitespace
- **THEN** reads and exports preserve its numeric precision or exact text while applying the published bounds
