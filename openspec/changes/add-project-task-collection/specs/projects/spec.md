## Purpose

Let an organization turn an explicit cohort of immutable dataset revisions and a published form into a frozen, attributable collection run.

## ADDED Requirements

### Requirement: Explicit organization-scoped project management
Project operations SHALL resolve targets within an explicit organization and require an active authenticated account, active organization, active membership, and `projects.read` for inspection or `projects.manage` for authoring and lifecycle changes. Choosing source datasets and forms SHALL additionally require their existing read capabilities. Management SHALL authorize its mutation result without implying general read access. New permissions SHALL require explicit role grants. Every project SHALL have an immutable organization and stable UUID identity; the MVP SHALL use that ID and its editable title without a separate textual project key. Foreign and nonexistent references SHALL fail without distinguishable disclosure.

#### Scenario: A manager creates a project
- **WHEN** an authorized manager selects readable dataset and form definitions in their organization
- **THEN** a draft project is created with that organization and its own stable identity

#### Scenario: Missing or foreign authority fails closed
- **WHEN** an inactive account, inactive organization/member, non-member, or actor lacking the operation's capability requests project data or supplies a foreign child
- **THEN** no unauthorized record is disclosed or changed

### Requirement: One explicit immutable cohort and contract
A project SHALL pin one dataset, one published schema version of that dataset, one published form version of the same organization, and an explicit nonempty cohort containing at most one revision per stable dataset item. All revisions SHALL use the pinned schema version. Every slot SHALL have an exact positive group size within its published bounds, and every requirement SHALL bind to one root field of the pinned schema with identical family/cardinality. Required requirements SHALL bind required fields. Each cohort revision SHALL be compatible with every slot's bindings; present assets SHALL be ready. Task groups SHALL contain distinct items across all slots. No form/question copy per item SHALL be created.

#### Scenario: A pairwise project uses reusable definitions
- **WHEN** a project binds a two-item candidate slot to compatible text fields and enrolls explicit revisions
- **THEN** its tasks can compare pairs while retaining one published form and the same question identities

#### Scenario: Invalid bindings leave the project editable
- **WHEN** activation finds a draft form, mixed-schema cohort, missing binding, wrong-family field, required-to-optional binding, unready asset, or insufficient distinct items
- **THEN** activation fails atomically with scoped issues and leaves the project draft

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze the cohort, dataset/schema/form references, bindings, slot counts/order policy, selection mode, audience/external-access mode, review mode, per-question policies, coverage target, and lease duration. Each form question SHALL have a positive accepted-answer target, skip permission, reason-required setting, and positive failure threshold. Selection SHALL be `balanced` or `explicit`; review SHALL be `automatic` or `manual`; lease duration SHALL be 1–120 minutes with a 30-minute default. Child edits and activation SHALL serialize so an edit is either included in validation or rejected after freezing. Authorized activation retries SHALL return the existing active project. After activation only title, lifecycle, and explicit per-user allow/block overrides SHALL be editable.

#### Scenario: A draft edit races activation
- **WHEN** enrollment or policy editing competes with activation
- **THEN** either the complete edit commits first and is validated, or activation commits first and the edit fails without modifying the frozen contract

#### Scenario: New imports do not enter active work
- **WHEN** another revision or dataset item is imported after activation
- **THEN** the active project's cohort and every issued input remain unchanged; enrollment requires a new project

### Requirement: Explicit groups are validated before use
An explicit-selection project SHALL define a finite ordered collection of groups whose inputs use its cohort and exact slot counts. Group identity SHALL ignore display shuffling but preserve slot membership. Duplicate canonical groups SHALL be rejected. Before activation every cohort item SHALL appear in at least the configured positive coverage target number of distinct groups. Unissued explicit groups SHALL remain configuration, not allocated tasks or worker evidence.

#### Scenario: Equivalent authored groups are rejected
- **WHEN** two explicit groups contain the same items in the same slots but reverse display order
- **THEN** the project rejects the duplicate rather than creating duplicate work

#### Scenario: Explicit coverage is impossible
- **WHEN** the authored groups do not cover an enrolled item to the configured target
- **THEN** activation fails with a scoped configuration error

### Requirement: Deliberate project lifecycle and retention
Projects SHALL allow state changes `draft -> active`, `active <-> paused`, `active|paused -> completed`, and `completed -> archived`. After current management authorization and under the project lock, activation, pause, resume, completion, and archive SHALL return the unchanged project successfully when it is already in that operation's target state. Such no-op retries SHALL not repeat freezing, expiration, cancellation, or timestamp updates. Other state-changing transitions SHALL be rejected. When the current state differs from the requested target, the action SHALL follow the normal transition rules rather than replaying an earlier result. Pause SHALL stop new allocations while allowing otherwise authorized unexpired attempts to finish. Completion SHALL take one database wall-clock cutoff after acquiring the exclusive project lock. In the same transaction it SHALL first mark physically live attempts whose deadlines are at or before that cutoff expired, then cancel remaining unexpired live attempts and unsatisfied tasks, updating reservations/progress consistently. It SHALL preserve submitted and satisfied evidence and prevent later allocation/submission. Overdue attempts SHALL retain expiry provenance and failure contribution rather than becoming deliberate cancellations. Completion SHALL be permitted before coverage satisfaction and without pausing first. Completed/archived projects SHALL retain authorized result inspection, review corrections, and exports. No project deletion or implicit completion on empty fetch SHALL be exposed.

#### Scenario: A lifecycle response is lost
- **WHEN** a caller repeats activation, pause, resume, completion, or archive while the project is already in that operation's target state
- **THEN** current management authorization is rechecked and an authorized retry returns the unchanged project without repeating transition effects; a caller whose authority was revoked is denied

#### Scenario: Pausing preserves work already issued
- **WHEN** a manager pauses an active project while a worker has an unexpired eligible attempt
- **THEN** fetch/assignment stop, but that worker can save and submit before lease expiry

#### Scenario: Completion races submission
- **WHEN** completion and a submission compete
- **THEN** either submission commits before completion and its evidence is preserved, or completion commits first and submission fails without a partial response

#### Scenario: Completion fails during cancellation
- **WHEN** cancellation or its progress update fails within project completion
- **THEN** the project transition, expirations, and cancellations roll back together; successful completion leaves overdue attempts expired, remaining live attempts and unsatisfied tasks cancelled, and reservations released in direct reads as well as GraphQL

#### Scenario: Completion precedes delayed expiry cleanup
- **WHEN** completion obtains the project lock after one live row's lease deadline while another live row remains unexpired
- **THEN** it records the first as expired with its failure contribution and the second as deliberately cancelled at the completion cutoff; both release reservations and later expiry jobs cannot change either terminal outcome

### Requirement: Activation accepts only implemented task contracts
Activation SHALL support scalar answers, non-image static/task-input choices, rankings, text spans, and asset requirements intended for opaque download. It SHALL reject any form containing an `image` input requirement, a bound-value presentation referencing an image requirement, an `image_choice` renderer, or a bounding-box, polygon-region, or raster-mask question with `unsupported_task_contract`, leaving the project draft. It SHALL validate the whole pinned form rather than silently dropping unsupported elements/questions. Published image-form definitions SHALL remain valid for authoring and inspection. No media service, decoder, verified dimensions, spatial-response tables, or mask-upload operation SHALL be required to implement or complete this release. Adding a media provider alone SHALL not enable the deferred contracts; the later task-media change SHALL explicitly extend execution support.

#### Scenario: Image execution is outside the installed task contract
- **WHEN** a manager activates a published image-choice or image-annotation form, even if an image provider has been configured separately
- **THEN** activation returns `unsupported_task_contract` without changing the draft or the published form

#### Scenario: A mixed form is rejected as a whole
- **WHEN** a pinned form contains supported text questions alongside an image presentation or spatial question
- **THEN** activation fails rather than issuing a partial version of the form contract

#### Scenario: Text collection works with no media support
- **WHEN** a valid scalar, non-image choice/ranking, or text-span project is activated with no detailed-media component installed
- **THEN** it can proceed through allocation, submission, review, and results without a media lookup

### Requirement: Project authoring and paginated inspection
Project, cohort, binding, policy, worker-access, and explicit-group collections SHALL use stable Relay keyset pagination following the existing API conventions, including nested collections. This change SHALL add no application-level cohort, explicit-group, input-group, or enrollment-batch size ceiling. Published form compatibility and existing foundation request validation SHALL still apply, and invalid writes SHALL fail atomically. Configured answer/coverage targets, failure thresholds, and answer integers SHALL retain signed 32-bit GraphQL Int semantics. Evidence-derived counts, including progress, failures, item coverage, and export record totals, SHALL use GraphQL String containing the exact canonical nonnegative base-10 integer, without sign, leading zeros, fraction, or exponent; zero SHALL be `"0"`. Their storage and arithmetic SHALL support values beyond signed 32-bit range without clamping to targets.

#### Scenario: A cohort spans multiple pages
- **WHEN** a manager traverses a frozen cohort larger than one page
- **THEN** every enrolled revision is reachable in stable order without an unbounded nested list

#### Scenario: An enrollment batch contains an invalid reference
- **WHEN** an enrollment request mixes valid revisions with a foreign or incompatible revision
- **THEN** none of that batch is enrolled
