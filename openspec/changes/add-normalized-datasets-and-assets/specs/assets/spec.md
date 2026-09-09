## Purpose

Provide immutable, organization-owned media assets that dataset values and future task responses can reference without embedding binary content or storage-provider details in product records.

## ADDED Requirements

### Requirement: Organization-scoped asset management
The system SHALL require an active authenticated account, an active owning organization, an active membership in that organization, and the appropriate asset capability for every caller-initiated asset-management action. Asset reads SHALL fail closed unless the organization is active and the actor is authorized through it or a future explicitly authorized product relationship.

#### Scenario: Authorized manager registers an asset
- **WHEN** an active member of an active organization with the asset-management capability registers an asset for that organization
- **THEN** the system creates a pending organization-owned asset and returns the provider-neutral information required to upload its content

#### Scenario: Non-member cannot inspect an asset
- **WHEN** an authenticated user without an authorized relationship requests an organization's asset or storage location
- **THEN** the system returns a fail-closed authorization error without exposing asset metadata or content location

#### Scenario: Inactive organization cannot access assets
- **WHEN** a member retains an active membership and asset capability in an organization that is inactive
- **THEN** caller-initiated asset management and reads are denied without exposing asset metadata or storage access

### Requirement: Immutable content-addressed assets
The system SHALL identify ready asset content by a SHA-256 hash supplied at registration as exactly 64 lowercase hexadecimal characters, validated and decoded once, and retained as a raw 32-byte binary in Elixir, storage-adapter facts, and PostgreSQL. GraphQL output and textual storage keys SHALL encode that binary as lowercase hexadecimal. Content identity SHALL also include byte size and media type. It SHALL reject a declared byte size over a configured positive maximum before issuing upload access. Every writable staging path SHALL enforce the declared byte-size cap through the configured provider or adapter before upload access is issued; registration SHALL fail closed when the configured storage adapter cannot enforce that cap. Before publishing the canonical object, finalization SHALL pin a staging version or conditionally fence further writes, obtain its actual size through bounded metadata, reject a size over that maximum, and validate its hash, size, safely detected media type, and bounded image facts. These finalization checks remain defense in depth rather than replacing the upload cap. Only matching verified staging bytes may be conditionally published at the organization-and-hash canonical immutable location, and the adapter SHALL reverify the canonical object before returning success. Mismatched staging bytes SHALL NOT create or occupy the declared canonical key. Concurrent identical sealing SHALL conditionally create or verify and reuse that one canonical location rather than leaving per-registration sealed copies. The system SHALL NOT make an asset ready from facts observed before an unguarded copy or promotion. Reads SHALL target only the sealed object. The system SHALL identify or safely sniff the actual media type from the verified bytes rather than trusting the declaration, SHALL reject declared/actual mismatches and active document formats including HTML, XHTML, and SVG, and SHALL prevent the content identity of a ready asset from being changed. PDF publication SHALL be rejected as unsupported; a PDF header alone does not establish that a document is free of active content.

#### Scenario: Matching upload is finalized
- **WHEN** the storage adapter verifies that pending content matches the registered hash, byte size, and supported media type
- **THEN** the adapter seals the verified bytes outside the writable staging location and the asset becomes ready only after recording that immutable content location

#### Scenario: Oversized registration is rejected early
- **WHEN** a registration declares a byte size above the configured maximum
- **THEN** the system rejects it before creating staging content or returning upload access

#### Scenario: Unenforceable upload cap fails closed
- **WHEN** the configured storage adapter cannot enforce the declared byte-size cap on writable staging
- **THEN** registration returns no upload access and creates no writable staging object

#### Scenario: Unexpired upload access cannot replace ready content
- **WHEN** a client reuses a still-valid upload descriptor after the asset becomes ready
- **THEN** it can affect only the abandoned staging location and authorized reads continue returning the sealed verified bytes

#### Scenario: Concurrent staging overwrite cannot change sealed facts
- **WHEN** a client attempts to overwrite the writable staging object while finalization is verifying and sealing it
- **THEN** finalization either seals and verifies one pinned version or fails without readiness, and it never records a hash, size, media type, or dimensions from bytes other than the immutable object later served

#### Scenario: Mismatched upload is rejected
- **WHEN** uploaded content has a different hash, byte size, or unsupported media type
- **THEN** the asset does not become ready, the declared canonical hash key remains available to later correct content, and the system records a sanitized failure state

#### Scenario: Active or falsely declared content is rejected
- **WHEN** sealed bytes contain HTML, XHTML, SVG, or another unsupported active format, including when registered under a benign media type
- **THEN** finalization rejects the asset without issuing ready-content access or exposing storage metadata

#### Scenario: PDF publication is unsupported
- **WHEN** uploaded bytes have a PDF header, whether registered as PDF or plain text
- **THEN** finalization rejects publication and creates no canonical object, including for binary PDF payloads

#### Scenario: Another canonical upload does not hide mismatched staging
- **WHEN** a pending registration contains mismatched staging bytes and matching canonical content was published by another registration
- **THEN** finalization still verifies this registration's staging and records a content mismatch without adopting the canonical asset

#### Scenario: Truncated PNG content is rejected
- **WHEN** a purported PNG lacks a complete IHDR, valid chunk checksums, image-data chunks, or the terminal IEND
- **THEN** verification rejects it without publishing canonical content or recording ready dimensions

#### Scenario: Ready content cannot be replaced
- **WHEN** an actor attempts to replace the content or content identity of a ready asset
- **THEN** the system rejects the mutation and requires registration of a new asset

### Requirement: Ready-content deduplication is recoverable
The system SHALL enforce organization-scoped content-hash uniqueness only for ready assets. Failed uploads SHALL NOT reserve that ready identity permanently. Reuse of a canonical ready asset SHALL require the registering hash, byte size, and media type to match its immutable facts exactly; the system SHALL return an asset-identity conflict rather than silently returning a canonical asset with different facts. Concurrent finalization of identical content SHALL select one canonical ready asset deterministically and SHALL not expose a mutable or ambiguous content reference. An authorized GraphQL read of a duplicate SHALL expose its canonical asset as the related typed resource in addition to the canonical identifier.

#### Scenario: Correct upload follows a failed upload
- **WHEN** an organization registers a new upload for content whose earlier pending asset failed verification
- **THEN** the system accepts a new pending asset because the failed asset does not occupy the ready-content identity

#### Scenario: Concurrent identical uploads converge
- **WHEN** two pending assets in one organization concurrently finalize with the same verified hash, byte size, and media type
- **THEN** one becomes the canonical ready asset, both operations converge on its one canonical sealed object, the other records a sanitized `duplicate_content` terminal outcome with no sealed copy of its own, and both callers receive or can resolve the canonical ready asset

#### Scenario: Existing hash has different registered facts
- **WHEN** an organization registers a hash that already has a canonical ready asset but supplies a different byte size or media type
- **THEN** the system rejects canonical reuse with an asset-identity conflict and does not return metadata that contradicts the request

### Requirement: Staging expiry and finalizer claims remain enforced
The system SHALL assign staging an expiry and refuse to begin finalization after that expiry. Finalization SHALL acquire a bounded mutually exclusive claim under the asset lock and check its identity on post-I/O transitions. Expired claims MAY be replaced. A finalizer SHALL recheck its live claim before publication, use finite adapter deadlines, and reverify an existing canonical object before adopting it. Storage I/O SHALL occur outside database transactions. Automatic staging deletion and background publication recovery are deferred to `restore-operator-bootstrap-and-maintenance`; obsolete staging remains stored.

#### Scenario: Expired staging cannot begin finalization
- **WHEN** finalization obtains the asset lock after staging expiry
- **THEN** it records staging expiry without publishing new content

#### Scenario: A stale finalizer tries to commit
- **WHEN** a finalizer's claim expires or is replaced before its database transition
- **THEN** it cannot commit stale lifecycle facts

### Requirement: Image metadata and compatibility
The system SHALL record validated image dimensions for image assets and SHALL expose enough metadata for later form bindings and spatial answers to verify source compatibility. It SHALL enforce configured positive maximum width, height, and total pixel count by parsing bounded image metadata before full decode and SHALL reject excessive dimensions as a sanitized validation failure.

#### Scenario: Image dimensions are recorded
- **WHEN** a supported image asset is finalized successfully
- **THEN** the system records its positive width and height together with its immutable content facts

#### Scenario: Invalid image metadata is rejected
- **WHEN** content claims to be an image but valid dimensions cannot be determined
- **THEN** the system leaves the asset unusable and reports a sanitized validation failure

#### Scenario: Excessive image dimensions are rejected before decode
- **WHEN** sealed image headers declare a width, height, or pixel count over a configured maximum
- **THEN** finalization rejects the asset before full image decode and does not make the content ready

### Requirement: Provider-neutral authorized access
The system SHALL keep storage locations private and SHALL obtain upload or download access through a configurable asset-storage adapter. Returned access SHALL expire after the current time and no later than the requested expiry, SHALL be short-lived, scoped to the authorized asset operation, delivered only through authenticated encrypted transport such as HTTPS, and marked to prevent caching and referrer propagation. Access handling SHALL reject insecure or adapter-unapproved destinations and SHALL prevent storage credentials from being disclosed to them, including through redirects.

#### Scenario: Authorized access is short-lived
- **WHEN** an authorized actor requests access to a ready asset
- **THEN** the system returns a time-limited encrypted-transport access descriptor without exposing persistent storage credentials and with no-store/no-referrer handling

#### Scenario: Insecure access descriptor is rejected
- **WHEN** an adapter returns a credential-bearing descriptor or redirect that uses cleartext transport or an unapproved destination
- **THEN** the system rejects the descriptor without returning credentials or changing asset state

#### Scenario: Redirect cannot leak credentials
- **WHEN** storage access redirects toward an insecure or adapter-unapproved destination
- **THEN** access fails without disclosing storage credentials to that destination

#### Scenario: Storage adapter failure is contained
- **WHEN** the configured storage adapter cannot produce authorized access
- **THEN** the action fails without changing asset ownership, readiness, or content identity
