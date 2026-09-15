## MODIFIED Requirements

### Requirement: One explicit immutable cohort and contract
A project SHALL fix its source identities at creation: one dataset, one published schema version of that dataset, one published form version of the same organization. Before activation it SHALL define an explicit nonempty cohort containing at most one revision per stable dataset item. All revisions SHALL use the pinned schema version. Every slot SHALL have an exact positive group size within its published bounds, and every requirement SHALL bind to one root field of the pinned schema with identical family/cardinality. Required requirements SHALL bind required fields. Each cohort revision SHALL be compatible with every slot's bindings; present assets SHALL be ready. Task groups SHALL contain distinct items across all slots. No form/question copy per item SHALL be created.

#### Scenario: A pairwise project uses reusable definitions
- **WHEN** a project binds a two-item candidate slot to compatible text fields and enrolls explicit revisions
- **THEN** its tasks can compare pairs while retaining one published form and the same question identities

#### Scenario: Invalid bindings leave the project editable
- **WHEN** activation finds a draft form, mixed-schema cohort, missing binding, wrong-family field, required-to-optional binding, unready asset, or insufficient distinct items
- **THEN** activation fails atomically with scoped issues and leaves the project draft

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze the cohort, bindings, explicit groups, slot counts/order policy, audience/external-access mode, review mode, submission target, project-wide skip rules, and lease duration. Dataset/schema/form identities SHALL be immutable from creation, including in draft. Each task SHALL require the project's positive `submission_target` (default 1, maximum 2,147,483,647). `skip_allowed` and `reason_required` SHALL default to false and apply to the whole form. Review SHALL be automatic or manual; leases SHALL be 1–120 minutes with a 30-minute default. Activation SHALL create no tasks, coverage rows, or progress projections. Child edits and activation SHALL serialize under the Project lock. After activation only title, lifecycle, and per-user allow/block overrides SHALL be editable.

#### Scenario: A draft edit races activation
- **WHEN** enrollment, grouping, or policy editing competes with activation
- **THEN** the complete edit is either included in activation validation or rejected after freezing

#### Scenario: An import arrives after activation
- **WHEN** a later revision is imported
- **THEN** the frozen cohort and all issued inputs remain unchanged

#### Scenario: A manager changes worker access
- **WHEN** an authorized manager edits an active project's per-user override
- **THEN** the edit rechecks current management authority under the Project lock without reopening configuration

### Requirement: Explicit groups are validated before use
Every project SHALL define a finite ordered collection of nonempty groups whose inputs use its cohort and exact slot counts. Group identity SHALL ignore display order but preserve slot membership. Duplicate canonical groups and duplicate items within a group SHALL be rejected. Every enrolled item SHALL appear in at least one group before activation. Unissued groups SHALL remain configuration rather than allocated tasks or worker evidence. Automatic/balanced grouping and coverage targets SHALL not be part of this contract.

#### Scenario: Equivalent authored groups are rejected
- **WHEN** two groups contain the same items in the same slots but reverse display order
- **THEN** the duplicate is rejected

#### Scenario: An enrolled item is absent from the groups
- **WHEN** activation finds an item absent from every authored group
- **THEN** activation fails and the project remains draft

### Requirement: Deliberate project lifecycle and retention
Projects SHALL allow state changes `draft -> active`, `active <-> paused`, `active|paused -> completed`, and `completed -> archived`. After current management authorization and under the project lock, activation, pause, resume, completion, and archive SHALL return the unchanged project successfully when it is already in that operation's target state. Such no-op retries SHALL not repeat freezing, expiration, cancellation, or timestamp updates. Other state-changing transitions SHALL be rejected. When the current state differs from the requested target, the action SHALL follow the normal transition rules rather than replaying an earlier result. Pause SHALL stop new allocations while allowing otherwise authorized unexpired attempts to finish. Completion SHALL take one database wall-clock cutoff after acquiring the exclusive project lock. In the same transaction it SHALL first mark physically live attempts whose deadlines are at or before that cutoff expired, then cancel remaining unexpired live attempts and unsatisfied tasks. It SHALL preserve submitted and satisfied evidence and prevent later allocation/submission. Overdue attempts SHALL retain expiry provenance rather than becoming deliberate cancellations. Completion SHALL be permitted before all submissions are collected and without pausing first. Completed/archived projects SHALL retain authorized result inspection, review corrections, and exports. No project deletion or implicit completion on empty fetch SHALL be exposed.

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
- **WHEN** cancellation fails within project completion
- **THEN** the project transition, expirations, and cancellations roll back together; successful completion leaves overdue attempts expired, remaining live attempts and unsatisfied tasks cancelled, and no remaining live capacity in direct reads as well as GraphQL

#### Scenario: Completion precedes delayed expiry cleanup
- **WHEN** completion obtains the project lock after one live row's lease deadline while another live row remains unexpired
- **THEN** it records the first as expired and the second as deliberately cancelled at the completion cutoff; both cease occupying capacity and later expiry jobs cannot change either terminal outcome

### Requirement: Project authoring and paginated inspection
Project creation, draft configuration, renaming, and lifecycle changes SHALL use native Ash create/update actions and domain interfaces. GraphQL SHALL use native mutations returning result/errors, with explicit organization-scoped manager-authorized lookups for updates. Dataset/schema/form references SHALL be chosen only on create. Bindings, slot policies, and worker-access overrides SHALL use native child-resource create/upsert and destroy actions returning the affected child through result/errors mutations. Destroy actions SHALL require explicit organization/project scope, use manager-authorized child lookups, and recheck the requested organization under the Project lock; domain destroy interfaces SHALL take the child record and organization scope. Child editing operations SHALL retain complete transaction and Project-lock validation. Project, cohort, binding, slot-policy, worker-access, and group collections SHALL use bounded Relay keyset pagination. This change SHALL add no application-level cohort, group, or enrollment-batch ceiling. Configured submission targets and scalar answer integers SHALL retain signed 32-bit GraphQL Int bounds.

#### Scenario: A manage-only actor changes a title
- **WHEN** an active member with projects.manage but no projects.read updates a project through its scoped mutation
- **THEN** the mutation returns the authorized result without granting general project inspection

#### Scenario: A draft source reference is changed
- **WHEN** a caller attempts to change its dataset, schema, or form after creation
- **THEN** the input is rejected; a different contract requires a new project

#### Scenario: A cohort spans pages
- **WHEN** a manager traverses more than one page of frozen cohort items
- **THEN** every item is reachable in stable order
