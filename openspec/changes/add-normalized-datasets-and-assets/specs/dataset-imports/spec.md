## Purpose

Provide provenance-preserving, idempotent programmatic imports that create or revise normalized dataset items safely while reporting row-level outcomes for large or partially invalid batches.

## ADDED Requirements

### Requirement: Organization-scoped import authorization
The system SHALL require an active authenticated account, an active dataset-owning organization, an active membership in that organization, and the appropriate dataset-import capability for every caller-initiated open, append, finalize, or inspect action. Finalization SHALL authorize and create a durable organization-owned processing command pinned to that batch's organization, dataset, and schema version. Internal retries SHALL advance only that accepted immutable scope and SHALL NOT reauthorize the initiating user's later account, membership, capability, or the organization's later active state. Organization deactivation SHALL deny all new caller actions and inspection but SHALL NOT implicitly cancel an already finalized import or grant access to other organization data.

#### Scenario: Authorized importer starts a batch
- **WHEN** an active member of an active organization with the import capability starts an import against that organization's dataset and published schema version
- **THEN** the system creates an import batch scoped to that dataset, organization, actor, and a schema version that belongs to that dataset

#### Scenario: Cross-organization import is denied
- **WHEN** an actor attempts to import into a dataset outside an authorized organization scope
- **THEN** the system rejects the action without accepting rows or revealing prior import details

#### Scenario: Revocation blocks new actions without rewriting accepted work
- **WHEN** the initiating actor loses account, membership, or capability access after an authorized import has been finalized
- **THEN** subsequent caller actions are denied, while the internal worker may finish only the already accepted organization-scoped rows without consulting or exposing any broader data

#### Scenario: Organization deactivation suspends access but not accepted work
- **WHEN** an organization becomes inactive after one of its imports was authorized and finalized
- **THEN** private processing may advance only that already pinned import while every caller-initiated import action and outcome inspection is denied until the organization is active again

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
The system SHALL persist a caller-stable row key, customer external key, unique source position, request fingerprint, and terminal outcome directly on every accepted import row. The request fingerprint SHALL use a versioned, domain-separated, length-prefixed canonical encoding with explicit null/present markers and canonical representations for the row key, external key, source position, and every other immutable row parameter, and SHALL embed the same canonical typed record stream used by item-revision fingerprints. The import and row key SHALL form a database identity, import plus source position SHALL be unique, and import plus non-null external key SHALL form a partial database identity. A matching append retry SHALL return the already accepted row without reconstructing or reprocessing it; reuse of either idempotency identity with a changed external key, normalized content, or other immutable parameter SHALL fail with an idempotency conflict. Once one append commits an external-key identity, any different row attempting that external key in the same import SHALL be rejected with `duplicate_external_key` before acceptance, regardless of worker scheduling.

For valid input, the append action SHALL transactionally persist an immutable normalized candidate `DatasetRecord` using the pinned schema version's designated root record type and a typed value graph whose fields belong to that exact record type, referenced by the import row. The worker SHALL consume those relational records by identity and SHALL NOT place dataset content in an opaque payload column or Oban job argument. For invalid input, the system SHALL persist the failed import-row outcome and sanitized validation error without persisting a partial candidate record or item revision.

#### Scenario: Identical row append returns the accepted row
- **WHEN** a caller repeats an append with the same import, row key, external key, source position, and request fingerprint
- **THEN** the system returns the original row and does not validate, stage, or process the content again

#### Scenario: Conflicting row append is rejected
- **WHEN** a caller reuses an import-scoped row key or source position with a different external key, normalized content, or other immutable parameter
- **THEN** the system rejects the append with an idempotency-conflict error

#### Scenario: Duplicate external key is rejected
- **WHEN** another row attempts to reserve an external key already accepted by the same import
- **THEN** the append fails with `duplicate_external_key`, no second row or candidate record is accepted, and the accepted row remains the only row allowed to revise that item

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

#### Scenario: Sibling record-type field is rejected
- **WHEN** a row for the schema's designated root type supplies a field that belongs only to another record type in the same schema version
- **THEN** the row records a sanitized invalid-field failure without creating a candidate record graph or item revision

#### Scenario: Equivalent row requests converge
- **WHEN** retry input differs only in field order, equivalent decimal scale, equivalent UTC date-time offset, or caller occurrence order while every immutable row parameter is unchanged
- **THEN** the shared canonical encoder produces the same row request fingerprint and append returns the accepted row without reprocessing

### Requirement: Finalization seals the accepted row set
The system SHALL create every import in the `open` state. It SHALL serialize append and finalization actions by locking the same import row and rechecking its lifecycle state. Append SHALL persist a row only while the locked import is `open`. Finalization SHALL atomically seal the import out of `open` before enqueuing processing, and no later append SHALL be accepted. The sealed import SHALL immediately expose the post-finalization state derived by the batch lifecycle rules.

#### Scenario: Append races finalization
- **WHEN** an append begins against an open import but finalization acquires the import lock and seals the batch first
- **THEN** the append observes that the import is no longer open, fails with `import_not_open`, and cannot add an unprocessed row to the sealed batch

#### Scenario: Open import remains appendable
- **WHEN** an authorized caller appends a unique row before finalization
- **THEN** the import remains `open`, accepts the row, and does not begin worker processing

### Requirement: Partial batch completion
The system SHALL process each import row atomically and SHALL allow valid rows to succeed when other rows in the batch are invalid. It SHALL expose disjoint counts derived directly from persisted rows: `accepted` counts every persisted `DatasetImportRow`; `pending`, `processing`, `succeeded`, and `unchanged` count their exact row outcomes; and `failed` counts every persisted terminal failure, including append-validation and processing failures. A `duplicate_external_key` rejection occurs before persistence and SHALL NOT increment accepted or failed. An `open` import SHALL remain `open` regardless of its current row outcomes. After finalization, the batch lifecycle SHALL use the following precedence so exactly one state applies:

| Sealed row condition | Batch state |
| --- | --- |
| At least one processing row has an unexpired lease | `processing` |
| Otherwise, at least one pending row or processing row with an expired lease exists | `pending` |
| No nonterminal rows exist and the accepted count is zero or the failed count is zero | `completed` |
| No nonterminal rows exist and every accepted row failed | `failed` |
| No nonterminal rows exist and failures coexist with succeeded or unchanged rows | `partially_failed` |

A processing row SHALL remain included in the processing count after lease expiry even though the expired lease makes the batch lifecycle `pending` and reclaimable. A processing claim SHALL record a start time, lease expiry, and incremented attempt count under a row lock, and SHALL return that attempt as a fencing token. Terminal writes SHALL succeed only while the row is still processing under the same attempt. Retries SHALL skip terminal rows and unexpired leases and SHALL reclaim expired processing leases safely without allowing an older worker to overwrite the reclaiming attempt. Before exiting while any active processing lease remains, the worker SHALL snooze itself or transactionally schedule one unique follow-up for the earliest lease expiry.

#### Scenario: Empty finalized batch completes
- **WHEN** an open import with zero accepted rows is finalized
- **THEN** it becomes `completed` with every row count equal to zero

#### Scenario: All successful rows complete
- **WHEN** every accepted row reaches a succeeded or unchanged terminal outcome
- **THEN** the batch becomes `completed` with zero pending, processing, and failed rows

#### Scenario: All failed rows fail the batch
- **WHEN** every accepted row reaches a failed terminal outcome
- **THEN** the batch becomes `failed` with failed count equal to accepted count

#### Scenario: Mixed batch completes partially
- **WHEN** a batch contains both valid and invalid rows
- **THEN** valid item revisions commit, invalid item revisions and partial record graphs remain non-persistent, failed import-row outcomes remain stored, and the batch finishes in a partially failed state with accurate counts

#### Scenario: Rejected duplicate does not alter row counts
- **WHEN** an append is rejected with `duplicate_external_key` before a second row is persisted
- **THEN** accepted and failed counts remain derived only from the already persisted rows

#### Scenario: Active lease keeps the batch processing
- **WHEN** a sealed batch has an unexpired processing lease even if other rows are terminal or pending
- **THEN** the batch state is `processing` and a unique follow-up is guaranteed no later than the earliest active lease expiry

#### Scenario: Expired lease makes the batch pending
- **WHEN** a sealed batch has no active lease and contains a processing row whose lease expired
- **THEN** the batch state is `pending` until a worker automatically reclaims that row

#### Scenario: Unexpected processor failure is retryable
- **WHEN** processing stops because of an unexpected transient failure
- **THEN** completed row outcomes remain idempotent and unfinished rows can be retried without duplicating revisions

#### Scenario: Worker crash leaves a reclaimable row
- **WHEN** a worker crashes after claiming a row but before recording its terminal outcome
- **THEN** another worker leaves the active lease untouched, guarantees a scheduled follow-up for its expiry, later reclaims it automatically, and safely processes the persisted normalized candidate without duplicating a revision

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
The system SHALL accept an asset value only when the referenced asset is ready, belongs to the same organization as the dataset, and passed sealed-byte media verification. Active document formats including HTML, XHTML, and SVG and declared/actual media-type mismatches SHALL be rejected during asset finalization and SHALL never become importable ready assets. In the first release, every remaining ready same-organization asset is compatible with a field whose value family is `asset`; form-specific media-type and dimension restrictions are deferred to later form bindings.

#### Scenario: Ready organization asset is imported
- **WHEN** a normalized row references a ready compatible asset owned by the dataset's organization
- **THEN** the item revision stores a relational asset value referencing that asset

#### Scenario: Invalid asset reference is rejected
- **WHEN** a row references a pending, failed, or cross-organization asset, or references an asset from a non-asset field
- **THEN** the row fails without exposing restricted asset metadata or creating a partial item revision

#### Scenario: Active or falsely declared asset is not importable
- **WHEN** a row references HTML, XHTML, SVG, or content whose declared media type did not match its sealed bytes
- **THEN** the asset cannot be ready and the row receives the same sanitized invalid-reference failure without restricted metadata exposure or a partial item revision
