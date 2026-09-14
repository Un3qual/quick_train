# task-responses Specification

## Purpose

Collect attributable typed answers and explicit skips against the exact questions and immutable inputs offered to each worker attempt.

## Requirements

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

### Requirement: Missing answered and skipped are distinct
Every offered question SHALL have exactly one explicit answered or skipped outcome before submission. Questions absent from the offered set SHALL be rejected even when they belong to the same form. A skip SHALL be allowed only by its frozen project-question policy and SHALL contain no answer value, a server timestamp, a nonblank reason when required, and an optional explanation. An all-skipped response SHALL be valid if every offered policy allows it. Skips SHALL satisfy no accepted-answer target and SHALL remain immutable queryable evidence even after a later follow-up answers the question.

#### Scenario: Absence is not a skip
- **WHEN** a worker submits without an offered question outcome
- **THEN** submission fails rather than inferring a skip or empty answer

#### Scenario: A draft answer is replaced by a skip
- **WHEN** an authorized worker skips a previously answered draft question whose policy allows it
- **THEN** the outcome and removal of all previous answer children commit together

#### Scenario: A skip requires a reason
- **WHEN** the project requires reasons and the worker supplies only whitespace
- **THEN** submission rejects that skip without freezing the response

### Requirement: Typed answers retain published form semantics
Ash create validations SHALL enforce scalar payload compatibility for ordinary and bulk question-response writes: only answered outcomes may contain scalar values, and each populated scalar field SHALL match the answer family. This rule SHALL live in Elixir rather than a PostgreSQL business-rule check; scoped foreign keys, uniqueness, and simple value bounds SHALL remain database integrity constraints.

Answered outcomes SHALL use exactly their published answer family and matching normalized typed representation, never JSONB answer content. The system SHALL support text, integer, decimal, boolean, static single/multiple choice, task-input single/multiple choice, and complete task-input ranking. Constraints SHALL come from the pinned published question, including the published meanings of absent scalar constraint records. Integers SHALL fit signed 32-bit Int; decimals SHALL preserve precision and reject non-finite values; text SHALL preserve exact valid Unicode content/whitespace and reject NUL. Single choice SHALL select exactly one valid option/input, multiple choice SHALL contain unique selections within bounds, and ranking SHALL be a complete unique ordered permutation of the question's slot inputs. Options SHALL belong to the exact question and TaskInputs to the exact task and referenced slot. Drafts can be incomplete but SHALL enforce local types, ownership, and the applicable published constraints before submission.

#### Scenario: A foreign option is supplied
- **WHEN** an answer references an option from a different question or published version
- **THEN** it fails without revealing or persisting the foreign relationship

#### Scenario: A ranking omits an input
- **WHEN** a ranking contains duplicates, missing inputs, or inputs from another slot/task
- **THEN** submission fails rather than storing a partial or ambiguous ranking

#### Scenario: Decimal and text values retain meaning
- **WHEN** a valid answer contains a high-precision decimal or text with significant whitespace
- **THEN** reads and exports preserve its numeric precision or exact text while applying the published bounds

### Requirement: Text-span provenance is exact
Each text span SHALL identify the exact TaskInput, its bound source DatasetValue, and a label from the question's published label set. The source SHALL match the question's required source requirement and the TaskInput's immutable revision. Annotation count bounds SHALL apply across all spans for that question outcome; zero entries SHALL count as answered only when the minimum is zero. Foreign labels, wrong source values, and unallocated inputs SHALL fail. Dataset values and answer values SHALL remain separate ownership/lifecycle models.

#### Scenario: An annotation points at another source field
- **WHEN** a worker supplies an existing value from the same revision that is not the question's bound source
- **THEN** the annotation is rejected rather than accepted merely because the revision matches

### Requirement: Text spans use code-point offsets
Text spans SHALL use zero-based Unicode code-point offsets with an exclusive end against exact immutable source text, satisfying `0 <= start < end <= code_point_length`. No normalization SHALL alter that source. Overlapping spans SHALL be allowed; exact duplicates of input/value/label/start/end SHALL be rejected. This capability SHALL not require image support.

#### Scenario: Multibyte text is annotated
- **WHEN** a worker annotates a source containing emoji or combining characters
- **THEN** offsets count Unicode code points, not UTF-8 bytes or displayed grapheme clusters, and out-of-range offsets fail

### Requirement: Response writes are explicitly exposed
GraphQL SHALL expose deliberate typed save/submit operations returning Attempt with its revision and paginated typed outcomes. Outcomes SHALL identify their owning attempt; separate Response query roots SHALL not exist. GraphQL SHALL expose paginated typed outcome inspection; generic submitted-outcome/child update and delete mutations SHALL not exist. Responses SHALL satisfy the pinned published form constraints and existing HTTP request behavior. This change SHALL add no separate answer/reason/explanation byte limit, offered-question cap, span-count ceiling, or combined annotation budget. Invalid operations SHALL fail atomically and all collections SHALL follow existing Relay keyset pagination conventions.

#### Scenario: A span answer violates its published contract
- **WHEN** a draft replacement violates the pinned question's published annotation constraint
- **THEN** the whole question write fails without replacing the previous draft answer
