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
The system SHALL identify ready asset content by a cryptographic hash, byte size, and media type. Upload access SHALL target a unique writable staging object. Before the ready transition, the storage adapter SHALL verify the staged content and idempotently promote or seal it at an immutable key or provider version that no issued upload descriptor can modify. Reads SHALL target only that sealed object. The system SHALL reject finalization when uploaded content does not match the registered facts, and it SHALL prevent the content identity of a ready asset from being changed.

#### Scenario: Matching upload is finalized
- **WHEN** the storage adapter verifies that pending content matches the registered hash, byte size, and supported media type
- **THEN** the adapter seals the verified bytes outside the writable staging location and the asset becomes ready only after recording that immutable content location

#### Scenario: Unexpired upload access cannot replace ready content
- **WHEN** a client reuses a still-valid upload descriptor after the asset becomes ready
- **THEN** it can affect only the abandoned staging location and authorized reads continue returning the sealed verified bytes

#### Scenario: Mismatched upload is rejected
- **WHEN** uploaded content has a different hash, byte size, or unsupported media type
- **THEN** the asset does not become ready and the system records a sanitized failure state

#### Scenario: Ready content cannot be replaced
- **WHEN** an actor attempts to replace the content or content identity of a ready asset
- **THEN** the system rejects the mutation and requires registration of a new asset

### Requirement: Ready-content deduplication is recoverable
The system SHALL enforce organization-scoped content-hash uniqueness only for ready assets. Failed uploads SHALL NOT reserve that ready identity permanently. Reuse of a canonical ready asset SHALL require the registering hash, byte size, and media type to match its immutable facts exactly; the system SHALL return an asset-identity conflict rather than silently returning a canonical asset with different facts. Concurrent finalization of identical content SHALL select one canonical ready asset deterministically and SHALL not expose a mutable or ambiguous content reference.

#### Scenario: Correct upload follows a failed upload
- **WHEN** an organization registers a new upload for content whose earlier pending asset failed verification
- **THEN** the system accepts a new pending asset because the failed asset does not occupy the ready-content identity

#### Scenario: Concurrent identical uploads converge
- **WHEN** two pending assets in one organization concurrently finalize with the same verified hash, byte size, and media type
- **THEN** one becomes the canonical ready asset, the other records a sanitized `duplicate_content` terminal outcome, and both callers receive or can resolve the canonical ready asset

#### Scenario: Existing hash has different registered facts
- **WHEN** an organization registers a hash that already has a canonical ready asset but supplies a different byte size or media type
- **THEN** the system rejects canonical reuse with an asset-identity conflict and does not return metadata that contradicts the request

### Requirement: Abandoned staging content expires
The system SHALL assign every writable staging object an expiry and SHALL remove expired staging content idempotently after a fixed safety grace period when its registration is pending, failed, in the `duplicate_content` terminal state, or already sealed. Cleanup SHALL NOT delete or mutate sealed read objects.

#### Scenario: Pending upload is abandoned
- **WHEN** a pending registration remains unfinalized beyond its staging expiry and cleanup grace period
- **THEN** the responsibility-named cleanup path removes its writable staging object and leaves the registration unable to become ready without a new upload

#### Scenario: Duplicate staging object is removed
- **WHEN** a losing concurrent finalization is in the `duplicate_content` terminal state beyond its staging expiry and cleanup grace period
- **THEN** cleanup removes that registration's redundant writable staging object without changing the canonical ready asset

#### Scenario: Cleanup preserves ready content
- **WHEN** cleanup processes a registration whose content has already been sealed
- **THEN** it may remove only the obsolete staging object and authorized reads continue returning the immutable sealed object

### Requirement: Image metadata and compatibility
The system SHALL record validated image dimensions for image assets and SHALL expose enough metadata for later form bindings and spatial answers to verify source compatibility.

#### Scenario: Image dimensions are recorded
- **WHEN** a supported image asset is finalized successfully
- **THEN** the system records its positive width and height together with its immutable content facts

#### Scenario: Invalid image metadata is rejected
- **WHEN** content claims to be an image but valid dimensions cannot be determined
- **THEN** the system leaves the asset unusable and reports a sanitized validation failure

### Requirement: Provider-neutral authorized access
The system SHALL keep storage locations private and SHALL obtain upload or download access through a configurable asset-storage adapter. Returned access SHALL be short-lived, scoped to the authorized asset operation, delivered only through authenticated encrypted transport such as HTTPS, and marked to prevent caching and referrer propagation. The system SHALL reject any credential-bearing descriptor or redirect chain that uses an insecure transport or escapes the adapter-approved secure destination.

#### Scenario: Authorized access is short-lived
- **WHEN** an authorized actor requests access to a ready asset
- **THEN** the system returns a time-limited encrypted-transport access descriptor without exposing persistent storage credentials and with no-store/no-referrer handling

#### Scenario: Insecure access descriptor is rejected
- **WHEN** an adapter returns a credential-bearing descriptor or redirect that uses cleartext transport or an unapproved destination
- **THEN** the system rejects the descriptor without returning credentials or changing asset state

#### Scenario: Storage adapter failure is contained
- **WHEN** the configured storage adapter cannot produce authorized access
- **THEN** the action fails without changing asset ownership, readiness, or content identity
