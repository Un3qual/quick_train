## Purpose

Provide provenance-preserving, idempotent programmatic imports that create or revise normalized dataset items safely while reporting row-level outcomes for large or partially invalid batches.

## ADDED Requirements

### Requirement: Organization-scoped import authorization
The system SHALL require an active authenticated account, an active dataset-owning organization, an active membership in that organization, and the dataset-import capability for every caller-initiated open, append, finalize, or inspect action. Finalization SHALL authorize a durable command pinned to the accepted import's organization, dataset, and schema version. Internal retries SHALL advance only that immutable scope and SHALL NOT grant access to any other organization data.

#### Scenario: Authorized importer starts a batch
- **WHEN** an active member of an active organization with the import capability starts an import against that organization's dataset and published schema version
- **THEN** the system creates an import scoped to that organization, dataset, actor, and same-dataset schema version

#### Scenario: Cross-organization import is denied
- **WHEN** an actor attempts to import into a dataset outside an authorized organization scope
- **THEN** the system rejects the action without accepting rows or revealing import details

#### Scenario: Revocation blocks new actions without rewriting accepted work
- **WHEN** the initiating actor later loses account, membership, or capability access after an import is finalized
- **THEN** caller actions are denied while internal retries may finish only the already accepted organization-scoped rows

### Requirement: Idempotent import batches
The system SHALL accept a caller-supplied idempotency key and associate it with a fingerprint of the schema version and immutable open parameters. Organization, dataset, and idempotency key SHALL form a unique identity. Matching sequential or concurrent requests SHALL return one import, while reusing that identity for changed parameters SHALL fail with `idempotency_conflict`.

#### Scenario: Identical retry returns one batch
- **WHEN** a caller repeats an open request with the same organization, dataset, idempotency key, and immutable parameters
- **THEN** the system returns the original import and creates no duplicate batch

#### Scenario: Conflicting retry is rejected
- **WHEN** a caller reuses the batch identity with a different schema version or immutable parameter
- **THEN** the system rejects the request with `idempotency_conflict`

### Requirement: Structurally accepted rows preserve provenance
The append API SHALL accept exactly one bounded flat row per call, composed of a row key, optional customer external key, source position, and typed field entries. It SHALL enforce configured positive limits on accepted rows per import, field entries per row, total scalar bytes per row, individual text bytes, and GraphQL request bytes before canonicalization, sorting, hashing, candidate construction, or row-identity reservation. Its fixed input shape SHALL reject unsupported nesting. Malformed scalar representations and unsupported value shapes SHALL likewise fail request validation before an import row or row idempotency identity is accepted. For every structurally accepted row, the system SHALL persist its row key, optional external key, unique source position, deterministic request fingerprint, and outcome. The fingerprint SHALL cover the pinned schema and every immutable accepted row parameter, including an external-key presence marker and the length-prefixed persisted external-key value when present, and SHALL be independent of field order and equivalent decimal or UTC date-time representations.

The import and row key SHALL form a unique identity, import plus source position SHALL be unique, and import plus non-null external key SHALL permit only one accepted row. A matching retry SHALL return the accepted row without reconstructing or reprocessing it. Reusing the row key or source position for changed accepted input SHALL fail with `idempotency_conflict`. A second row targeting an already accepted external key in the same import SHALL fail with `duplicate_external_key` before persistence.

#### Scenario: Identical row retry returns the accepted row
- **WHEN** a caller repeats a structurally accepted append with the same immutable row input
- **THEN** the system returns the original row without staging or processing the content again

#### Scenario: Conflicting row retry is rejected
- **WHEN** a caller reuses an import-scoped row key or source position for changed accepted input
- **THEN** the system rejects the append with `idempotency_conflict`

#### Scenario: Duplicate external key is rejected
- **WHEN** another row attempts an external key already accepted by the same import
- **THEN** the append fails with `duplicate_external_key` before creating a second row or candidate record

#### Scenario: Malformed input is rejected before acceptance
- **WHEN** append input contains a malformed scalar representation, unsupported value shape, or nested record
- **THEN** request validation fails without reserving a row key or source position and without persisting an import row or opaque payload

#### Scenario: Oversized input is rejected before canonicalization
- **WHEN** an append or import exceeds a configured request, row, field, scalar-byte, or text-byte limit
- **THEN** the system rejects it before sorting, fingerprinting, constructing a candidate, or reserving row provenance

#### Scenario: Equivalent accepted input converges
- **WHEN** a retry differs only in field order, equivalent decimal scale, or equivalent UTC date-time offset
- **THEN** it has the same request identity and returns the accepted row

### Requirement: Accepted rows stage normalized candidates or terminal validation failures
For a structurally accepted row, the append action SHALL validate field keys, value-family selectors, cardinality, required values, and asset relationships against the pinned published schema. Valid input SHALL transactionally persist an immutable normalized candidate `DatasetRecord` and typed values referenced by a pending import row. Domain-invalid input SHALL persist a failed row outcome and sanitized validation errors without persisting a partial candidate record or item revision. The system SHALL NOT retain an opaque request payload.

For a valid row without an external key, the persisted import-row UUID SHALL be its target dataset-item UUID. Processing SHALL create or lock that exact item and commit its revision and row outcome atomically; append alone SHALL NOT create an empty item.

#### Scenario: Valid new row creates an item
- **WHEN** a pending row contains a complete normalized record under a new external key
- **THEN** processing creates one stable item and records success with its first immutable revision

#### Scenario: Changed row creates a revision
- **WHEN** a pending row targets an existing external key with changed valid content
- **THEN** processing records success and references the new immutable revision

#### Scenario: Unchanged row reuses the latest revision
- **WHEN** a pending row targets an existing item with content and schema identical to its latest revision
- **THEN** processing records `unchanged` and references that revision without creating another

#### Scenario: Domain-invalid row records failure
- **WHEN** structurally accepted input has a missing required value, type mismatch, unknown field, duplicate single-cardinality field, or unauthorized asset reference
- **THEN** the row records a sanitized terminal failure without a partial candidate graph or item revision

#### Scenario: Keyless retry targets one item
- **WHEN** processing a valid keyless row is retried after a worker failure
- **THEN** every attempt targets the row-derived item UUID and at most one item and revision outcome commit

#### Scenario: Sibling record-type field is rejected
- **WHEN** a row for the designated root type supplies a field that belongs to another record type in the same schema
- **THEN** the row records a sanitized field failure without creating a candidate graph or revision

### Requirement: Finalization seals the accepted row set
Every import SHALL begin in persisted phase `open` with a server-calculated immutable expiry. Append and finalization SHALL lock the same import and recheck its phase and expiry. The first valid finalization SHALL atomically change the phase to `sealed` and insert one row-identity-unique bounded-retry processing job for every pending row; failure to insert the complete job set SHALL roll back sealing. A sealed import SHALL accept no later row. An expired open import SHALL reject append and first finalization with `import_expired`. Matching sequential or concurrent finalization retries SHALL return the same sealed import and SHALL not enqueue duplicate processing.

#### Scenario: Append races finalization
- **WHEN** finalization seals the import before a concurrent append acquires its lock
- **THEN** the append fails with `import_not_open` and adds no row

#### Scenario: Lost finalization response is retry safe
- **WHEN** finalization commits but its response is lost
- **THEN** a retry returns the sealed import and exactly one processing job exists for each pending row

#### Scenario: Expired open import rejects work
- **WHEN** append or first finalization locks an open import after its expiry
- **THEN** it fails with `import_expired` and creates no row or processing job

### Requirement: Abandoned open imports expire
Automatic cleanup SHALL scan expired open imports, lock the same import row used by append and finalization, recheck both facts, and delete only that abandoned import with its unprocessed rows and candidate records. Cleanup SHALL never delete a sealed import or finalized provenance. Successful cleanup SHALL release the abandoned batch idempotency identity.

#### Scenario: Abandoned import is cleaned
- **WHEN** an import remains open beyond its lifetime
- **THEN** automatic cleanup removes its rows and candidate records without creating or deleting a dataset item revision

#### Scenario: Cleanup loses to valid finalization
- **WHEN** finalization locks and verifies an import before expiry while cleanup later waits for the same row
- **THEN** finalization may seal it and cleanup skips the sealed provenance

#### Scenario: Finalization reaches an expired import
- **WHEN** finalization first locks the import after expiry
- **THEN** it returns `import_expired` and leaves the open import eligible for cleanup

### Requirement: Row processing is idempotent and retryable
Finalization SHALL atomically insert the complete set of unique durable bounded-retry jobs for pending rows rather than relying on a separate fan-out worker. A row job SHALL lock the row, return without work when it is already terminal, and atomically commit its item revision reference and terminal `succeeded`, `unchanged`, or `failed` outcome. A worker failure before that commit SHALL leave the row pending so standard job retry can try again. A retry after the commit SHALL observe the terminal row and SHALL not duplicate an item revision. When retry exhaustion or cancellation leaves no runnable attempt, the system SHALL automatically and atomically record sanitized `processing_retries_exhausted` failure so the import cannot remain pending indefinitely. The capability contract does not mandate a periodic scanner, pruning coordination, custom row-processing lease, persisted row attempt counter, attempt fence, or per-attempt recovery job.

#### Scenario: Row-job scheduling is atomic with sealing
- **WHEN** finalization cannot insert the complete unique job set for all pending rows
- **THEN** sealing rolls back and a retry may attempt the same complete operation without leaving a sealed import with unscheduled rows

#### Scenario: Row worker fails before commit
- **WHEN** a row worker raises or exits before its atomic terminal transaction commits
- **THEN** the row remains pending and Oban may retry the same row job

#### Scenario: Row worker loses success acknowledgement
- **WHEN** a row transaction commits but the job attempt is retried before Oban records success
- **THEN** the retry observes the terminal row and exits without creating another revision

#### Scenario: Retry exhaustion becomes terminal provenance
- **WHEN** a unique row job exhausts its bounded attempts or is cancelled while its import row remains pending
- **THEN** the system records one sanitized failed outcome without manual intervention, allowing the sealed batch to leave `pending`

### Requirement: Batch progress is derived from rows
An import SHALL persist only its `open` or `sealed` phase. It SHALL NOT persist aggregate outcome counters or a separate processing lifecycle. Queries SHALL derive `row_count`, `pending`, `succeeded`, `unchanged`, and `failed` from current import rows. These mutually exclusive counts SHALL sum to `row_count`. An open import's lifecycle SHALL be `open`; a sealed import with any pending row SHALL be `pending`; a sealed import with no pending rows SHALL be `completed` when no row failed, `failed` when every nonempty row set failed, and `partially_failed` when failures coexist with succeeded or unchanged rows. An empty sealed import SHALL be `completed`.

#### Scenario: Empty sealed batch completes
- **WHEN** an import with no accepted rows is finalized
- **THEN** it is `completed` and every derived count is zero

#### Scenario: Mixed batch completes partially
- **WHEN** valid rows succeed or remain unchanged and other rows fail
- **THEN** the batch is `partially_failed` with counts derived from the retained row outcomes

#### Scenario: Pending row keeps batch pending
- **WHEN** a sealed import contains at least one row without a terminal outcome
- **THEN** its lifecycle is `pending` regardless of other terminal rows

#### Scenario: Concurrent completions remain visible
- **WHEN** independent workers complete different rows concurrently
- **THEN** later progress queries derive both committed outcomes without relying on a serialized counter snapshot

### Requirement: Concurrent revisions remain ordered
The system SHALL atomically get or create the stable dataset item for a supplied dataset-scoped external key and SHALL serialize revision creation on that item so revision numbers remain monotonic and one content change does not produce duplicate revisions. Keyless rows SHALL use and lock their row-derived item identity.

#### Scenario: Concurrent updates target one item
- **WHEN** workers concurrently process changed rows for the same dataset item
- **THEN** they lock the authoritative item, create revisions in a valid order, and preserve unique revision identities

#### Scenario: Concurrent rows target an unseen external key
- **WHEN** workers first encounter the same dataset-scoped external key concurrently
- **THEN** they converge on one atomically created item before revision comparison

### Requirement: Import schemas and assets stay in scope
The system SHALL require an import schema to be published and belong to the import's dataset. It SHALL accept an asset value only when the asset is ready, belongs to the dataset's organization, and has passed sealed-byte media verification. Cross-dataset schemas and pending, failed, active-format, falsely declared, or cross-organization assets SHALL fail without exposing restricted metadata or creating partial records.

#### Scenario: Foreign schema is rejected
- **WHEN** an actor opens or processes an import with a schema from another dataset
- **THEN** the system rejects it without accepting rows or creating cross-dataset references

#### Scenario: Ready organization asset is imported
- **WHEN** a valid row references a ready asset owned by the dataset's organization
- **THEN** the candidate record stores a relational asset value referencing it

#### Scenario: Invalid asset reference is rejected
- **WHEN** a row references a pending, failed, unsupported, or cross-organization asset
- **THEN** the row records a sanitized failure without exposing asset metadata or creating a partial revision
