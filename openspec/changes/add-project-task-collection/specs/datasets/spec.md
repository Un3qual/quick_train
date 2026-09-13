## ADDED Requirements

### Requirement: Attempt-owned bound-value inspection
The system SHALL allow an eligible owner of an unexpired live task attempt in an active or paused project to read only the values bound by that project's frozen input requirements from its exact allocated immutable item revisions. It SHALL recheck active account/organization, current audience route, absence of a block, ownership, and lease on every access. This explicit product relationship SHALL not require dataset capability or organization membership and SHALL not grant general dataset, cohort, schema, item, revision, or unbound-value browsing. Returned values SHALL identify their TaskInput, requirement, field, revision, value occurrence, and typed value; absent optional values SHALL remain explicit. Typed persistence children SHALL remain inaccessible through unrestricted direct reads. Every to-many work-bundle relationship SHALL use bounded Relay keyset pagination, default 50/max 100. Existing management authorization and immutable revision/content rules SHALL remain unchanged.

#### Scenario: An external worker reads only allocated fields
- **WHEN** an eligible non-member opens an allocated input from a revision containing both bound and unbound fields
- **THEN** the work bundle exposes the bound fields and their exact provenance without revealing unbound values or other revisions

#### Scenario: A newer revision exists
- **WHEN** the dataset item receives a new revision after allocation
- **THEN** the work bundle and later submitted evidence continue identifying the allocated revision and its original values

#### Scenario: A direct typed-child read is attempted
- **WHEN** a worker uses an exposed value identifier to request an unrestricted typed-value resource or reverse relationship
- **THEN** access fails without bypassing the attempt-owned field restriction

### Requirement: Result-scoped bound-value inspection
An active member authorized for `tasks.results.read` in an active organization and explicit project scope SHALL be able to inspect the frozen bindings and exact bound values of TaskInputs referenced by eligible result evidence through Tasks without `datasets.read`. Reads and exports SHALL preserve revision, field, value, requirement, and slot identities, exact typed values, and explicit optional absence. Only bound values from those issued inputs SHALL be eligible; no unbound fields, unissued cohort items, later revisions, or general dataset traversal SHALL be exposed. Result relationships SHALL use bounded typed pagination and SHALL not grant direct access to unrestricted typed-value resources.

#### Scenario: A result reader resolves ranked inputs
- **WHEN** an authorized result-only reader inspects a ranking whose source revisions also contain private unbound fields
- **THEN** the original bound input content and binding meanings are available in ranked order, while unbound content remains inaccessible
