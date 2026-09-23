## ADDED Requirements

### Requirement: Native authoring mutation contracts
Schema draft creation/publication and record-type/field creation, update, and removal SHALL expose native typed mutation inputs and result/errors envelopes with generated domain interfaces. They SHALL preserve explicit organization authorization, transactional parent locking, draft immutability, version allocation, and scoped child identity.

#### Scenario: Native child edit races publication
- **WHEN** a scoped child mutation races schema publication
- **THEN** parent serialization preserves the existing edit-before-publication or rejection-after-publication behavior

### Requirement: Consistent bounded scalar normalization
Direct revisions and import rows SHALL agree on persisted scalar validity, including rejecting non-finite decimals before fingerprinting and record construction. Input type restrictions, exact text, decimal bounds, and import error staging SHALL remain unchanged. Incoming row validation SHALL load required and supplied field definitions without loading unrelated optional definitions; persisted candidate processing SHALL load definitions only for its actual values.

#### Scenario: Non-finite decimal input
- **WHEN** a caller supplies NaN or positive or negative infinity as a decimal
- **THEN** scalar validation rejects it before content fingerprinting or persistence

#### Scenario: Small row in a wide schema
- **WHEN** a bounded row uses a small subset of a schema's optional fields
- **THEN** validation includes supplied and required definitions without hydrating unrelated optional fields
