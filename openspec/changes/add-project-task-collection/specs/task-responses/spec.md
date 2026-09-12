## Purpose

Collect attributable typed answers and explicit skips against the exact questions and immutable inputs offered to each worker attempt.

## ADDED Requirements

### Requirement: One draft becomes one immutable submission
Each attempt SHALL own at most one Response that transitions from mutable draft to immutable submitted. Save SHALL require the current eligible owner and unexpired live attempt in an active or paused project. Every question outcome/child write or delete SHALL serialize with submission on the same draft and recheck its state. Saves SHALL replace one complete question outcome atomically, require the current `expected_revision`, and increment that revision; stale revisions SHALL fail without overwriting newer work. Submission SHALL atomically validate all and only offered questions, freeze the response and descendants, transition the attempt, and update capacity/review evidence. An authorized submit retry SHALL return the existing submission without duplicating outcomes or automatic reviews. Released/expired/cancelled drafts SHALL never become submitted.

#### Scenario: A save races submission
- **WHEN** a question save and submit run concurrently
- **THEN** either the whole save is included in the validated submission or submission wins and the save fails; no descendant changes after freezing

#### Scenario: A stale client saves over newer work
- **WHEN** the supplied response revision differs from its current revision
- **THEN** the write returns `stale_response` without changing any outcome

#### Scenario: Submission fails on one question
- **WHEN** one offered outcome is missing or invalid
- **THEN** no response, attempt, reservation, or review transition commits and the valid draft remains editable while the lease permits

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
Answered outcomes SHALL use exactly their published answer family and matching normalized typed representation, never JSONB answer content. The system SHALL support text, integer, decimal, boolean, static single/multiple choice, task-input single/multiple choice, and complete task-input ranking. Constraints SHALL come from the pinned published question, including the published meanings of absent scalar constraint records. Integers SHALL fit signed 32-bit Int; decimals SHALL preserve precision and reject non-finite values; text SHALL preserve exact valid Unicode content/whitespace and reject NUL. Single choice SHALL select exactly one valid option/input, multiple choice SHALL contain unique selections within bounds, and ranking SHALL be a complete unique ordered permutation of the question's slot inputs. Options SHALL belong to the exact question and TaskInputs to the exact task and referenced slot. Drafts can be incomplete but SHALL enforce local types, ownership, and finite limits before submission.

#### Scenario: A foreign option is supplied
- **WHEN** an answer references an option from a different question or published version
- **THEN** it fails without revealing or persisting the foreign relationship

#### Scenario: A ranking omits an input
- **WHEN** a ranking contains duplicates, missing inputs, or inputs from another slot/task
- **THEN** submission fails rather than storing a partial or ambiguous ranking

#### Scenario: Decimal and text values retain meaning
- **WHEN** a valid answer contains a high-precision decimal or text with significant whitespace
- **THEN** reads and exports preserve its numeric precision or exact text while applying the published bounds

### Requirement: Annotation provenance is exact
Each spatial region or text span SHALL identify the exact TaskInput, its bound source DatasetValue, and a label from the question's published label set. The source SHALL match the question's required source requirement and the TaskInput's immutable revision. Annotation count bounds SHALL apply across all regions/spans for that question outcome; zero entries SHALL count as answered only when the minimum is zero. Foreign labels, wrong source values, and unallocated inputs SHALL fail. Dataset values and answer values SHALL remain separate ownership/lifecycle models.

#### Scenario: An annotation points at another source field
- **WHEN** a worker supplies an existing value from the same revision that is not the question's bound source
- **THEN** the annotation is rejected rather than accepted merely because the revision matches

### Requirement: Bounding boxes and polygons use normalized valid geometry
Bounding boxes SHALL use finite normalized coordinates with `0 <= x_min < x_max <= 1` and `0 <= y_min < y_max <= 1`. Polygon regions SHALL contain at least three distinct ordered points within `[0,1]`, have nonzero area, and form a simple non-self-intersecting ring with implicit closure. Repeated closing points, holes within one region, and non-finite coordinates SHALL be rejected. Multiple independent regions SHALL be permitted within count limits. Image execution SHALL require the separately implemented verified-media and serving prerequisites; opaque readiness alone SHALL not validate image sources.

#### Scenario: Invalid geometry is submitted
- **WHEN** a box has negative width or a polygon crosses itself or contains an out-of-range coordinate
- **THEN** submission fails without persisting an immutable invalid annotation

#### Scenario: Media capability is unavailable
- **WHEN** an image attempt cannot resolve the required verified source facts or supported image-serving capability
- **THEN** fetch/submission fails closed rather than trusting client image metadata

### Requirement: Raster masks reference compatible immutable assets
A raster mask SHALL reference a ready immutable mask asset and exact source asset/value with verified positive source dimensions. A separately implemented media capability SHALL verify compatible encoding and source/mask pixel dimensions and bind that result to both immutable asset identities; client dimensions and declared media types SHALL not satisfy it. Mask registration/finalization SHALL require a live eligible owning attempt and an offered raster-mask question, use the project's organization and existing upload-cap/hash/sealing rules, and create an explicit attempt/question attachment authority. Canonical deduplication SHALL preserve that authority without granting general asset reuse/browsing rights. Tasks SHALL not decode files or select a provider in this change.

#### Scenario: The source and mask have different dimensions
- **WHEN** the media capability reports incompatible dimensions for the exact source and mask
- **THEN** submission rejects the mask

#### Scenario: A worker borrows another attempt's asset
- **WHEN** a worker references a ready mask without authorized attachment provenance for the offered question
- **THEN** the answer fails even if the asset belongs to the same organization

### Requirement: Text spans use code-point offsets
Text spans SHALL use zero-based Unicode code-point offsets with an exclusive end against exact immutable source text, satisfying `0 <= start < end <= code_point_length`. No normalization SHALL alter that source. Overlapping spans SHALL be allowed; exact duplicates of input/value/label/start/end SHALL be rejected. This capability SHALL not require image support.

#### Scenario: Multibyte text is annotated
- **WHEN** a worker annotates a source containing emoji or combining characters
- **THEN** offsets count Unicode code points, not UTF-8 bytes or displayed grapheme clusters, and out-of-range offsets fail

### Requirement: Response writes are bounded and explicitly exposed
GraphQL SHALL expose deliberate typed save/submit operations and bounded typed outcome inspection; generic submitted-outcome/child update and delete mutations SHALL not exist. Apply at most 200 offered questions, 64 KiB text per answer, 1 KiB reason, 16 KiB explanation, 1,000 regions per question, 1,000 points per polygon, and 10,000 annotation child rows per response, alongside published form bounds and the existing HTTP body limit. Impossible published minimums SHALL reject project activation; tighter execution ceilings SHALL be disclosed. Oversized operations SHALL fail atomically and all collections SHALL use Relay keyset pagination, default 50/max 100.

#### Scenario: A polygon exceeds its execution limit
- **WHEN** a draft write supplies 1,001 polygon points
- **THEN** the whole question write fails without replacing the previous draft answer
