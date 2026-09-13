## ADDED Requirements

### Requirement: PostgreSQL generates backend UUID identities
PostgreSQL SHALL be the generator for new persisted UUID record identities and internal UUID operation tokens across the existing backend foundations and new Projects/Tasks resources. Normal resource creation SHALL omit the ID and use a PostgreSQL `gen_random_uuid()` default; Ash SHALL treat the attribute as data-layer generated without an Elixir UUID default. Create operations SHALL return the stored database-generated identity, fetching the record when necessary. Application creation paths SHALL not generate replacement UUIDs in Elixir or accept a caller-selected new record ID. Existing persisted IDs and their references SHALL remain unchanged. Embedded projections SHALL copy the identity of their source record rather than generate another one. UUIDs that identify existing records SHALL remain ordinary reference inputs.

#### Scenario: A resource is created without an ID
- **WHEN** an authorized operation creates a resource through a direct Ash action or a workflow using bulk creation
- **THEN** PostgreSQL generates the new record ID and the returned record exposes that same stored identity for subsequent relationships and reads

#### Scenario: Identity generation changes on an existing database
- **WHEN** resource declarations and database defaults are aligned with PostgreSQL generation
- **THEN** existing users, forms, datasets, assets, and their references retain their original IDs and content while subsequent creates use database-generated IDs

### Requirement: Dependent writes use database-issued identities
Dependent rows and copied graphs SHALL reference the IDs returned from creating their owners. Form copying SHALL obtain fresh database-generated IDs and remap copied references within the existing atomic copy transaction, preserving the source graph. Where an internal workflow requires a UUID before insertion or for a finalizer claim, it SHALL obtain the value from PostgreSQL within that workflow's database transaction. Such preallocation SHALL not create a separate UUID registry or public reservation operation. Asset registration SHALL persist its database-issued Asset ID and derived staging destination before storage I/O; task-generated assets SHALL also persist their applicable task ownership in that transaction. Finalizer claims SHALL retain existing fencing, locking, expiry, and retry behavior using the database-issued claim token. A failed database operation SHALL not fall back to Elixir UUID generation or start storage work.

#### Scenario: A published form is copied
- **WHEN** a new draft copies a published form graph
- **THEN** each copied row receives a fresh database-generated ID, all copied internal references point to the corresponding copied rows, and the source graph remains unchanged; failure rolls back the copy

#### Scenario: Storage work needs an identity before upload
- **WHEN** an asset registration needs its ID to derive a staging destination
- **THEN** the transaction obtains the UUID from PostgreSQL and persists the Asset, destination, and any required task ownership before issuing upload access or writing bytes; subsequent upload/finalization and keyed task-workflow retries use that stored identity

### Requirement: Retry tokens are distinct from record identities
Allocation, manual review/correction, and export retry keys SHALL remain required caller-supplied UUID request inputs stored in their existing scoped UUID columns. They SHALL identify repeated requests and SHALL never become the ID of a newly created backend record. The backend SHALL validate supplied tokens without generating them in Elixir or introducing a token-issuance endpoint or generic retry ledger. Invalid or missing tokens SHALL fail before mutation. Existing same-key convergence and changed-argument conflict behavior SHALL remain in force.

#### Scenario: A creation response is lost
- **WHEN** an authorized caller retries an allocation, review, or export with the same valid token and arguments after the first request created its record but its response was lost
- **THEN** the operation returns its existing result with the original database-generated record identity, without requiring the caller to know that identity before the first request
