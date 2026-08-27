## Purpose

Provide immutable, organization-owned media assets that dataset values and future task responses can reference without embedding binary content or storage-provider details in product records.

## ADDED Requirements

### Requirement: Organization-scoped asset management
The system SHALL require an active authenticated account, an active membership in the owning organization, and the appropriate asset capability for every asset-management action. Asset reads SHALL fail closed unless the actor is authorized through the owning organization or a future explicitly authorized product relationship.

#### Scenario: Authorized manager registers an asset
- **WHEN** an active organization member with the asset-management capability registers an asset for that organization
- **THEN** the system creates a pending organization-owned asset and returns the provider-neutral information required to upload its content

#### Scenario: Non-member cannot inspect an asset
- **WHEN** an authenticated user without an authorized relationship requests an organization's asset or storage location
- **THEN** the system returns a fail-closed authorization error without exposing asset metadata or content location

### Requirement: Immutable content-addressed assets
The system SHALL identify ready asset content by a cryptographic hash, byte size, and media type. It SHALL reject finalization when uploaded content does not match the registered facts, and it SHALL prevent the content identity of a ready asset from being changed.

#### Scenario: Matching upload is finalized
- **WHEN** the storage adapter verifies that pending content matches the registered hash, byte size, and supported media type
- **THEN** the asset becomes ready and its content identity becomes immutable

#### Scenario: Mismatched upload is rejected
- **WHEN** uploaded content has a different hash, byte size, or unsupported media type
- **THEN** the asset does not become ready and the system records a sanitized failure state

#### Scenario: Ready content cannot be replaced
- **WHEN** an actor attempts to replace the content or content identity of a ready asset
- **THEN** the system rejects the mutation and requires registration of a new asset

### Requirement: Image metadata and compatibility
The system SHALL record validated image dimensions for image assets and SHALL expose enough metadata for later form bindings and spatial answers to verify source compatibility.

#### Scenario: Image dimensions are recorded
- **WHEN** a supported image asset is finalized successfully
- **THEN** the system records its positive width and height together with its immutable content facts

#### Scenario: Invalid image metadata is rejected
- **WHEN** content claims to be an image but valid dimensions cannot be determined
- **THEN** the system leaves the asset unusable and reports a sanitized validation failure

### Requirement: Provider-neutral authorized access
The system SHALL keep storage locations private and SHALL obtain upload or download access through a configurable asset-storage adapter. Returned access SHALL be short-lived and scoped to the authorized asset operation.

#### Scenario: Authorized access is short-lived
- **WHEN** an authorized actor requests access to a ready asset
- **THEN** the system returns a time-limited access descriptor without exposing persistent storage credentials

#### Scenario: Storage adapter failure is contained
- **WHEN** the configured storage adapter cannot produce authorized access
- **THEN** the action fails without changing asset ownership, readiness, or content identity
