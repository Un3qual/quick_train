## Purpose

Provide provenance-preserving, idempotent programmatic imports that create or revise normalized dataset items safely while reporting row-level outcomes for large or partially invalid batches.

## ADDED Requirements

### Requirement: Organization-scoped import authorization
The system SHALL require an active authenticated account, an active membership in the dataset's organization, and the appropriate dataset-import capability to create, append to, process, or inspect an import batch.

#### Scenario: Authorized importer starts a batch
- **WHEN** an active organization member with the import capability starts an import against an organization-owned dataset and published schema version
- **THEN** the system creates an import batch scoped to that dataset, organization, actor, and schema version

#### Scenario: Cross-organization import is denied
- **WHEN** an actor attempts to import into a dataset outside an authorized organization scope
- **THEN** the system rejects the action without accepting rows or revealing prior import details

### Requirement: Idempotent import batches
The system SHALL accept a caller-supplied idempotency key for each import batch and SHALL associate it with a request fingerprint. Repeating the same key and fingerprint SHALL return the existing batch, while reusing the key for different input SHALL fail with an idempotency conflict.

#### Scenario: Identical retry returns existing batch
- **WHEN** a caller repeats an import request with the same organization, dataset, idempotency key, and request fingerprint
- **THEN** the system returns the original batch and does not duplicate item revisions

#### Scenario: Conflicting retry is rejected
- **WHEN** a caller reuses an import idempotency key with a different request fingerprint
- **THEN** the system rejects the request with an idempotency-conflict error

### Requirement: Provenance-preserving row processing
The system SHALL record a stable row identity, customer external key, source position, and terminal outcome for every accepted import row. It SHALL preserve sanitized validation errors without storing dataset content in an opaque payload column.

#### Scenario: Valid new row creates an item
- **WHEN** a row supplies a new external key and a complete normalized record valid for the pinned schema version
- **THEN** the row records success and references the created item and first revision

#### Scenario: Valid changed row creates a revision
- **WHEN** a row supplies an existing external key with changed valid content
- **THEN** the row records success and references the newly created immutable item revision

#### Scenario: Unchanged retry does not create a revision
- **WHEN** a row supplies an existing external key with content identical to the latest revision
- **THEN** the row records an unchanged outcome and references the existing latest revision

#### Scenario: Invalid row records failure
- **WHEN** a row contains a missing required value, type mismatch, unknown field, unsupported structure, or unauthorized asset reference
- **THEN** that row records a sanitized failure and does not create a partial item revision

### Requirement: Partial batch completion
The system SHALL process each import row atomically and SHALL allow valid rows to succeed when other rows in the batch are invalid. The batch SHALL expose pending, processing, completed, partially failed, or failed lifecycle states derived from its row outcomes.

#### Scenario: Mixed batch completes partially
- **WHEN** a batch contains both valid and invalid rows
- **THEN** valid rows commit, invalid rows remain non-persistent, and the batch finishes in a partially failed state with accurate counts

#### Scenario: Unexpected processor failure is retryable
- **WHEN** processing stops because of an unexpected transient failure
- **THEN** completed row outcomes remain idempotent and unfinished rows can be retried without duplicating revisions

### Requirement: Concurrent revisions remain ordered
The system SHALL serialize concurrent imports that target the same stable dataset item so that at most one next revision is created for a given content change and revision numbers remain monotonic.

#### Scenario: Concurrent updates target one item
- **WHEN** two import workers concurrently process changed rows for the same dataset item
- **THEN** the system locks the authoritative item state, creates revisions in a valid order, and prevents duplicate revision identities

### Requirement: Asset references are validated
The system SHALL accept an asset value only when the referenced asset is ready, belongs to the same organization, and is compatible with the dataset field definition.

#### Scenario: Ready organization asset is imported
- **WHEN** a normalized row references a ready compatible asset owned by the dataset's organization
- **THEN** the item revision stores a relational asset value referencing that asset

#### Scenario: Invalid asset reference is rejected
- **WHEN** a row references a pending, failed, cross-organization, or incompatible asset
- **THEN** the row fails without exposing restricted asset metadata or creating a partial item revision
