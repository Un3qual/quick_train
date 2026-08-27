## Purpose

Provide organization-owned datasets whose schemas, items, revisions, records, and typed values remain queryable and historically unambiguous without JSONB-backed content or customer-specific tables.

## ADDED Requirements

### Requirement: Organization-scoped datasets
The system SHALL require an active authenticated account, an active membership in the owning organization, and the appropriate dataset capability for every dataset-management action. Dataset definitions, items, revisions, and values SHALL fail closed to unauthorized actors.

#### Scenario: Authorized manager creates a dataset
- **WHEN** an active organization member with the dataset-management capability creates a dataset
- **THEN** the system creates the dataset under that organization

#### Scenario: Cross-organization read is denied
- **WHEN** a member of another organization requests dataset content without another explicit authorized relationship
- **THEN** the system denies the request without revealing the dataset's schema, items, or values

### Requirement: Versioned normalized dataset schemas
The system SHALL represent a dataset schema through immutable published schema versions containing record types and typed field definitions. Field keys SHALL be unique within a record type, and every field SHALL declare its value family and cardinality.

#### Scenario: Valid schema version is published
- **WHEN** a draft schema version contains a root record type and valid uniquely keyed field definitions
- **THEN** the system publishes the version and prevents later structural mutation

#### Scenario: Invalid field definition is rejected
- **WHEN** a schema version contains duplicate field keys, an unsupported value family, or an invalid cardinality
- **THEN** publication fails with field-specific validation errors

#### Scenario: Published schema change creates a version
- **WHEN** an organization needs to change a published dataset schema
- **THEN** it creates and publishes a new schema version while existing item revisions retain the previous version

### Requirement: Stable items and immutable revisions
The system SHALL give each dataset item a stable identity within its dataset and SHALL store content changes as immutable, monotonically ordered item revisions. Every revision SHALL pin one published schema version and one root record.

#### Scenario: First revision is created
- **WHEN** valid content is added under a new customer external key
- **THEN** the system creates one stable item and its first immutable revision

#### Scenario: Changed content creates a revision
- **WHEN** valid changed content is accepted for an existing external key
- **THEN** the system preserves the existing revisions and creates the next immutable revision

#### Scenario: Historical revision remains unchanged
- **WHEN** a newer revision is created
- **THEN** reads of every older revision return the same schema version, record, and typed values as before

### Requirement: Normalized typed record values
The system SHALL store each item revision as a root dataset record containing field-associated value occurrences and normalized typed values. Dataset content SHALL NOT be stored in JSONB columns, and each value occurrence SHALL contain exactly one representation compatible with its field definition.

#### Scenario: Flat typed record is accepted
- **WHEN** a record supplies valid text, integer, decimal, boolean, date-time, or ready asset values for its schema fields
- **THEN** the system creates normalized value occurrences and typed value records linked to the root record

#### Scenario: Type mismatch is rejected
- **WHEN** a value representation does not match its field's declared value family
- **THEN** the record and containing item revision are rejected atomically

#### Scenario: Unknown field is rejected
- **WHEN** a record supplies a value for a field outside its pinned schema version
- **THEN** the system rejects the record without persisting a partial revision

#### Scenario: Required field is missing
- **WHEN** a record omits a required field occurrence
- **THEN** the system rejects the record with a field-specific validation error

### Requirement: Forward-compatible record envelope
The system SHALL assign stable identity and ordinal position to value occurrences so that repeated values and record-valued fields can be introduced additively. The first release SHALL accept only flat records and SHALL reject unsupported nested record input explicitly.

#### Scenario: Flat value has a stable occurrence
- **WHEN** a flat record value is created
- **THEN** it receives a stable value-occurrence identity and an ordinal compatible with future repeated values

#### Scenario: Nested value is not silently flattened
- **WHEN** a caller supplies a nested record value before nested records are supported
- **THEN** the system returns an unsupported-structure error and does not serialize the nested value into an opaque column

### Requirement: Deliberate GraphQL dataset API
The system SHALL expose authenticated GraphQL actions for dataset and schema lifecycle operations and paginated typed reads. It SHALL NOT expose unrestricted mutation of published schemas or immutable item revisions.

#### Scenario: Typed revision is queried
- **WHEN** an authorized actor queries an item revision
- **THEN** the API returns its schema identity, root record, field identities, ordinals, and typed values

#### Scenario: Immutable revision mutation is denied
- **WHEN** a caller attempts to update or delete value content through a generic mutation
- **THEN** no such public mutation is available and the record remains unchanged
