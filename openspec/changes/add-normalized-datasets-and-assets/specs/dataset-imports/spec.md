## Purpose

Provide provenance-preserving, idempotent programmatic imports that create or revise normalized dataset items safely while reporting row-level outcomes for large or partially invalid batches.

## ADDED Requirements

### Requirement: Organization-scoped import authorization
The system SHALL require an active authenticated account, an active membership in the dataset's organization, and the appropriate dataset-import capability for every caller-initiated open, append, finalize, or inspect action. Finalization SHALL authorize and create a durable organization-owned processing command pinned to that batch's organization, dataset, and schema version. Internal retries SHALL advance only that accepted scope and SHALL NOT gain access to other organization data.

#### Scenario: Authorized importer starts a batch
- **WHEN** an active organization member with the import capability starts an import against an organization-owned dataset and published schema version
- **THEN** the system creates an import batch scoped to that dataset, organization, actor, and a schema version that belongs to that dataset

#### Scenario: Cross-organization import is denied
- **WHEN** an actor attempts to import into a dataset outside an authorized organization scope
- **THEN** the system rejects the action without accepting rows or revealing prior import details

#### Scenario: Revocation blocks new actions without rewriting accepted work
- **WHEN** the initiating actor loses account, membership, or capability access after an authorized import has been finalized
- **THEN** subsequent caller actions are denied, while the internal worker may finish only the already accepted organization-scoped rows without consulting or exposing any broader data

### Requirement: Idempotent import batches
The system SHALL accept a caller-supplied idempotency key for each import batch and SHALL associate it with a request fingerprint covering the schema version and immutable open parameters. A database identity SHALL uniquely constrain organization, dataset, and idempotency key. Batch creation SHALL use an atomic create-or-return operation so matching concurrent requests return the same batch, while reusing the identity for a different fingerprint fails with an idempotency conflict.

#### Scenario: Identical retry returns existing batch
- **WHEN** a caller repeats an import request with the same organization, dataset, idempotency key, and request fingerprint
- **THEN** the system returns the original batch and does not duplicate item revisions

#### Scenario: Concurrent identical starts converge
- **WHEN** matching requests concurrently open a batch under the same organization, dataset, and idempotency key
- **THEN** exactly one batch is created and every caller receives that batch

#### Scenario: Conflicting retry is rejected
- **WHEN** a caller reuses an import idempotency key with a different request fingerprint
- **THEN** the system rejects the request with an idempotency-conflict error

### Requirement: Provenance-preserving row processing
The system SHALL persist a caller-stable row key, customer external key, unique source position, request fingerprint, and terminal outcome directly on every accepted import row. The request fingerprint SHALL cover the external key, source position, normalized content, and every other immutable row parameter. The import and row key SHALL form a database identity, and import plus source position SHALL also be unique. A matching append retry SHALL return the already accepted row without reconstructing or reprocessing it; reuse of either identity with a changed external key, normalized content, or other immutable parameter SHALL fail with an idempotency conflict.

For valid input, the append action SHALL transactionally persist an immutable normalized candidate `DatasetRecord` and typed value graph referenced by the import row. The worker SHALL consume those relational records by identity and SHALL NOT place dataset content in an opaque payload column or Oban job argument. For invalid input, the system SHALL persist the failed import-row outcome and sanitized validation error without persisting a partial candidate record or item revision.

#### Scenario: Identical row append returns the accepted row
- **WHEN** a caller repeats an append with the same import, row key, external key, source position, and request fingerprint
- **THEN** the system returns the original row and does not validate, stage, or process the content again

#### Scenario: Conflicting row append is rejected
- **WHEN** a caller reuses an import-scoped row key or source position with a different external key, normalized content, or other immutable parameter
- **THEN** the system rejects the append with an idempotency-conflict error

#### Scenario: Valid new row creates an item
- **WHEN** a row supplies a new external key and a complete normalized record valid for the pinned schema version
- **THEN** the append stores the normalized candidate record and processing records success referencing the created item and first revision

#### Scenario: Valid changed row creates a revision
- **WHEN** a row supplies an existing external key with changed valid content
- **THEN** the row records success and references the newly created immutable item revision

#### Scenario: Unchanged retry does not create a revision
- **WHEN** a row supplies an existing external key with content and schema version identical to the latest revision
- **THEN** the row records an unchanged outcome and references the existing latest revision

#### Scenario: Invalid row records failure
- **WHEN** a row contains a missing required value, type mismatch, unknown field, unsupported structure, or unauthorized asset reference
- **THEN** that row retains its customer external key and records a sanitized failure without creating a partial item revision

### Requirement: Finalization seals the accepted row set
The system SHALL serialize append and finalization actions by locking the same import row and rechecking its lifecycle state. Append SHALL persist a row only while the locked import is open. Finalization SHALL atomically transition the locked import out of open before enqueuing processing, and no later append SHALL be accepted.

#### Scenario: Append races finalization
- **WHEN** an append begins against an open import but finalization acquires the import lock and seals the batch first
- **THEN** the append observes that the import is no longer open, fails with `import_not_open`, and cannot add an unprocessed row to the sealed batch

### Requirement: Partial batch completion
The system SHALL process each import row atomically and SHALL allow valid rows to succeed when other rows in the batch are invalid. The batch SHALL expose pending, processing, completed, partially failed, or failed lifecycle states derived from its persisted row outcomes. A processing claim SHALL record a start time, lease expiry, and incremented attempt count under a row lock, and SHALL return that attempt as a fencing token. Terminal writes SHALL succeed only while the row is still processing under the same attempt. Retries SHALL skip terminal rows and unexpired leases and SHALL reclaim expired processing leases safely without allowing an older worker to overwrite the reclaiming attempt.

#### Scenario: Mixed batch completes partially
- **WHEN** a batch contains both valid and invalid rows
- **THEN** valid item revisions commit, invalid item revisions and partial record graphs remain non-persistent, failed import-row outcomes remain stored, and the batch finishes in a partially failed state with accurate counts

#### Scenario: Unexpected processor failure is retryable
- **WHEN** processing stops because of an unexpected transient failure
- **THEN** completed row outcomes remain idempotent and unfinished rows can be retried without duplicating revisions

#### Scenario: Worker crash leaves a reclaimable row
- **WHEN** a worker crashes after claiming a row but before recording its terminal outcome
- **THEN** another worker leaves the active lease untouched, later reclaims it after expiry, and safely processes the persisted normalized candidate without duplicating a revision

#### Scenario: Stalled worker resumes after reclamation
- **WHEN** an older worker resumes after its lease expired and another worker reclaimed the row with a higher attempt number
- **THEN** the older worker's terminal write is rejected by the attempt fence and cannot overwrite the current attempt's outcome

### Requirement: Concurrent revisions remain ordered
The system SHALL atomically get or create the stable dataset item for a supplied dataset-scoped external key and SHALL serialize revision creation on that authoritative item so that at most one next revision is created for a given content change and revision numbers remain monotonic.

#### Scenario: Concurrent updates target one item
- **WHEN** two import workers concurrently process changed rows for the same dataset item
- **THEN** the system locks the authoritative item state, creates revisions in a valid order, and prevents duplicate revision identities

#### Scenario: Concurrent rows target an unseen external key
- **WHEN** two import workers concurrently process rows for the same previously unseen dataset-scoped external key
- **THEN** both converge on one atomically created item before revision comparison and return valid changed or unchanged outcomes without exposing a uniqueness failure

### Requirement: Import schemas belong to their dataset
The system SHALL resolve an import's published schema version through its dataset and SHALL enforce the shared dataset identity in Ash actions and database constraints for imports, items, revisions, records, and fields.

#### Scenario: Foreign schema version is rejected
- **WHEN** an actor who can access multiple datasets attempts to open or process an import using a schema version from a different dataset
- **THEN** the system rejects the request without accepting rows, exposing foreign schema metadata, or creating cross-dataset references

### Requirement: Asset references are validated
The system SHALL accept an asset value only when the referenced asset is ready and belongs to the same organization as the dataset. In the first release, every such asset is compatible with a field whose value family is `asset`; media-type and dimension restrictions are deferred to later form bindings.

#### Scenario: Ready organization asset is imported
- **WHEN** a normalized row references a ready compatible asset owned by the dataset's organization
- **THEN** the item revision stores a relational asset value referencing that asset

#### Scenario: Invalid asset reference is rejected
- **WHEN** a row references a pending, failed, or cross-organization asset, or references an asset from a non-asset field
- **THEN** the row fails without exposing restricted asset metadata or creating a partial item revision
