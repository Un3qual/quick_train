# database-identities Specification

## Purpose

Keep persisted backend identities stable using Ash UUID primary keys while separating caller-supplied request tokens from record identities.

## Requirements

### Requirement: Ash generates backend UUID identities
Persisted resources across Accounts, Organizations, Authorization, EnterpriseIdentity, Forms, Datasets, Assets, Projects, and Tasks SHALL declare their UUID record identities with Ash's `uuid_primary_key`. Ordinary creation SHALL use its `Ash.UUID.generate/0` default. Existing PostgreSQL UUID columns and their normal AshPostgres migration defaults SHALL remain compatible with this declaration; no custom database-generation attribute configuration or SQL UUID allocation query SHALL be required. Application creation paths SHALL not accept caller-selected new record IDs. A private workflow MAY supply an internally generated UUID when it needs that identity before insertion. Create operations SHALL return the stored identity. Existing persisted IDs and their references SHALL remain unchanged. Embedded projections SHALL copy the identity of their source record rather than generate another one. UUIDs that identify existing records SHALL remain ordinary reference inputs.

#### Scenario: A resource is created without an ID
- **WHEN** an authorized operation creates a resource through a direct Ash action or a workflow using bulk creation
- **THEN** Ash generates its UUID and the returned record exposes that same stored identity for subsequent relationships and reads

#### Scenario: Identity generation changes on an existing database
- **WHEN** resources return to `uuid_primary_key` declarations
- **THEN** existing users, forms, datasets, assets, and their references retain their original IDs and content while subsequent creates use Ash-generated UUIDs

### Requirement: Dependent writes preserve generated identities
Dependent rows and copied graphs SHALL reference the IDs returned from creating their owners. Form copying SHALL obtain fresh UUIDs and remap copied references within the existing atomic copy transaction, preserving the source graph. Where an internal workflow requires a UUID before insertion, it SHALL use `Ash.UUID.generate/0` without a database allocation query, UUID registry, or public reservation operation. Ordinary Assets registration SHALL generate its UUID and derive the staging destination, then validate upload access outside a database transaction before creating the pending Asset with that same UUID as its record ID. Invalid access SHALL leave no pending registration, preserving the existing provider-neutral access contract. Task-generated assets SHALL atomically persist their Asset ID, staging destination, and applicable task ownership before storage I/O so their existing task workflow can resume that identity; access failures SHALL preserve the already-committed record without granting access. Finalizer claim UUIDs SHALL use `Ash.UUID.generate/0` and retain existing fencing, locking, expiry, and retry behavior. A failed task-registration transaction SHALL not start storage work.

#### Scenario: A published form is copied
- **WHEN** a new draft copies a published form graph
- **THEN** each copied row receives a fresh UUID, all copied internal references point to the corresponding copied rows, and the source graph remains unchanged; failure rolls back the copy

#### Scenario: Ordinary registration persists its generated UUID
- **WHEN** ordinary Assets registration generates a UUID, derives its staging destination, and validates upload access successfully
- **THEN** the pending Asset is created with that exact UUID as its ID and retains the destination derived from it, without generating a second UUID

#### Scenario: Ordinary registration receives invalid upload access
- **WHEN** ordinary Assets registration generates a UUID for its staging destination but the adapter returns an invalid descriptor
- **THEN** access fails without persisting a pending Asset or returning the descriptor; the unused UUID requires no reservation record or cleanup

#### Scenario: Task storage work needs a durable identity
- **WHEN** a task-generated asset needs its ID and ownership before upload access or backend writes
- **THEN** one transaction persists its internally generated UUID, staging destination, and task ownership before storage I/O; an access failure returns no descriptor and preserves that same record for the owning workflow's existing retry path

### Requirement: Retry tokens are distinct from record identities
Allocation, manual review/correction, and export retry keys SHALL remain required caller-supplied UUID request inputs stored in their existing scoped UUID columns. They SHALL identify repeated requests and SHALL never become the ID of a newly created backend record. The backend SHALL validate supplied tokens without generating them on behalf of callers or introducing a token-issuance endpoint or generic retry ledger. Invalid or missing tokens SHALL fail before mutation. Existing same-key convergence and changed-argument conflict behavior SHALL remain in force.

#### Scenario: A creation response is lost
- **WHEN** an authorized caller retries an allocation, review, or export with the same valid token and arguments after the first request created its record but its response was lost
- **THEN** the operation returns its existing result with the original record identity, without requiring the caller to know that identity before the first request
