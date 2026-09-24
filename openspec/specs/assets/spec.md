# assets Specification

## Purpose

Provide immutable, organization-owned media assets that dataset values and future task responses can reference without embedding binary content or storage-provider details in product records.

## Requirements

### Requirement: Organization-scoped asset management
The system SHALL require an active authenticated account, an active owning organization, an active membership in that organization, and the appropriate asset capability for every caller-initiated asset-management action. Asset reads SHALL fail closed unless the organization is active and the actor is authorized through it or a future explicitly authorized product relationship.

#### Scenario: Hash validation uses the supplied string
- **WHEN** an asset hash includes leading or trailing whitespace
- **THEN** registration rejects it as `invalid_asset_hash` rather than trimming it into a valid digest

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
The system SHALL identify ready asset content by a SHA-256 hash supplied at registration as exactly 64 lowercase hexadecimal characters, validated and decoded once, and retained as a raw 32-byte binary in Elixir, storage-adapter facts, and PostgreSQL. GraphQL output and textual storage keys SHALL encode that binary as lowercase hexadecimal. Content identity SHALL also include byte size and the declared, untrusted media type. It SHALL reject a declared byte size over a configured positive maximum before issuing upload access. Every writable staging path SHALL enforce the declared byte-size cap through the configured provider or adapter before upload access is issued; registration SHALL fail closed when the configured storage adapter cannot enforce that cap. Before publishing the canonical object, finalization SHALL pin a staging version or conditionally fence further writes, obtain its actual size through bounded metadata, reject a size over that maximum, and validate its hash and size. These finalization checks remain defense in depth rather than replacing the upload cap. Only matching verified staging bytes may be conditionally published at the organization-and-hash canonical immutable location, and the adapter SHALL reverify the canonical object before returning success. Mismatched staging bytes SHALL NOT create or occupy the declared canonical key. Concurrent identical sealing SHALL conditionally create or verify and reuse that one canonical location rather than leaving per-registration sealed copies. The system SHALL NOT make an asset ready from facts observed before an unguarded copy or promotion. Reads SHALL target only the sealed object. Files SHALL be treated as opaque bytes without format validation, parsing, sniffing, or dimension extraction. Readiness SHALL mean byte integrity and immutable storage, not safe rendering or decodability. Declared media type SHALL remain immutable untrusted metadata and SHALL NOT determine the download response type.

#### Scenario: Matching upload is finalized
- **WHEN** the storage adapter verifies that pending content matches the registered hash and byte size
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
- **THEN** finalization either seals and verifies one pinned version or fails without readiness, and it never records a hash or size from bytes other than the immutable object later served

#### Scenario: Mismatched upload is rejected
- **WHEN** uploaded content has a different hash or byte size
- **THEN** the asset does not become ready, the declared canonical hash key remains available to later correct content, and the system records a sanitized failure state

#### Scenario: Opaque file content is not interpreted
- **WHEN** matching bytes contain a document, an image, or an incomplete format header under any declared media type
- **THEN** finalization verifies byte integrity without claiming format validity, decodability, or safe inline rendering

#### Scenario: Another canonical upload does not hide mismatched staging
- **WHEN** a pending registration contains mismatched staging bytes and matching canonical content was published by another registration
- **THEN** finalization still verifies this registration's staging and records a content mismatch without adopting the canonical asset

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

#### Scenario: Pending uploads conflict on declared media type
- **WHEN** two pending registrations contain identical bytes but different declared media types and one occupies the canonical storage key
- **THEN** the other becomes failed with `asset_identity_conflict`, clears its finalizer claim, and returns that terminal outcome on retries

#### Scenario: Invalid media-type text is rejected before storage
- **WHEN** the declared media type is blank, invalid UTF-8, or contains NUL
- **THEN** registration fails with `invalid_media_type` before obtaining upload access or persisting an asset

### Requirement: Staging expiry and finalizer claims remain enforced
The system SHALL assign staging an expiry and refuse to begin finalization after that expiry. Finalization SHALL acquire a bounded mutually exclusive claim under the asset lock and check its identity on post-I/O transitions. Expired claims MAY be replaced. A finalizer SHALL recheck its live claim before publication, use finite adapter deadlines, and reverify an existing canonical object before adopting it. Storage I/O SHALL occur outside database transactions. Application-managed staging cleanup and background publication recovery remain deferred to `restore-operator-bootstrap-and-maintenance`. Production S3 staging SHALL follow the qualified provider-native retention rules defined by `http-asset-storage`, allowing obsolete staging objects and versions to expire after the configured safety window while protecting sealed content. Provider expiration SHALL NOT change asset database state, replace claim checks, or imply that bytes are deleted immediately at staging expiry. Local development reset and disposable test cleanup SHALL retain their existing scope without requiring a background cleanup worker.

#### Scenario: Expired staging cannot begin finalization
- **WHEN** finalization obtains the asset lock after staging expiry
- **THEN** it records staging expiry without publishing new content

#### Scenario: A stale finalizer tries to commit
- **WHEN** a finalizer's claim expires or is replaced before its database transition
- **THEN** it cannot commit stale lifecycle facts

#### Scenario: Provider retention removes obsolete staging
- **WHEN** qualified production lifecycle rules expire obsolete staging objects or versions after the configured safety window
- **THEN** that provider cleanup is permitted without an application cleanup worker, and sealed content, asset database state, staging-expiry enforcement, and finalizer-claim checks remain unchanged

### Requirement: Opaque download delivery
The system SHALL serve ready assets only as downloads. HTTP storage adapters SHALL enforce response headers `Content-Disposition: attachment`, `Content-Type: application/octet-stream`, and `Cache-Control: no-store` through provider metadata or authenticated response overrides. Download access SHALL target an approved HTTPS storage hostname distinct from application hostnames and outside the scope of application session cookies. HTTP storage configuration SHALL explicitly declare application hostnames and session-cookie Domain scopes, including consuming frontends; an explicitly empty domain list SHALL mean host-only cookies, while an omitted declaration SHALL fail validation. Validation SHALL reject storage hostnames equal to application hosts or equal to or beneath a declared cookie domain after DNS/domain normalization. Application cookies and bearer credentials SHALL NOT be sent to storage; the issued operation-scoped storage authorization SHALL authorize the transfer. Clients SHALL treat these URLs only as file-transfer access and SHALL NOT load them as scripts, stylesheets, or inline application content. An otherwise-compliant isolated download endpoint SHALL remain supported without `X-Content-Type-Options: nosniff`; where a delivery endpoint supplies that header, the system SHALL retain it. Attachment disposition, binary content type, and origin isolation SHALL NOT be represented as equivalent to nosniff's script/style MIME enforcement. Request headers in an access descriptor SHALL NOT be considered enforcement of response headers. Inline previews and image dimensions are deferred; existing nullable dimension fields SHALL remain unset on newly finalized assets.

#### Scenario: Declared media type does not control rendering
- **WHEN** an authorized client downloads an asset declared as HTML, PDF, or an image
- **THEN** the provider responds with attachment disposition, octet-stream content type, and no-store from the isolated storage host, independently of the declared media type

#### Scenario: Direct storage cannot set nosniff
- **WHEN** the configured direct storage endpoint enforces the mandatory download headers and isolation but cannot add nosniff
- **THEN** the adapter remains eligible and issues short-lived download access without requiring an application streaming route or a header-injection proxy

#### Scenario: Storage overlaps application credentials
- **WHEN** a proposed download destination shares an application hostname or falls within an application session cookie's scope
- **THEN** that deployment does not qualify for direct download delivery until the storage hostname and cookie scope are isolated

#### Scenario: Sibling hosts share a parent-domain session cookie
- **WHEN** the application uses `app.example.com`, storage uses `storage.example.com`, and an application session cookie declares Domain `.example.com`
- **THEN** configuration is rejected before issuing storage access despite the distinct hostnames

#### Scenario: Cookie scopes are undeclared
- **WHEN** storage configuration omits its application-cookie-domain declaration
- **THEN** configuration fails closed rather than assuming host-only cookies

### Requirement: Provider-neutral authorized access
The system SHALL keep storage locations private and SHALL obtain upload or download access through a configurable asset-storage adapter. Returned access SHALL expire after the current time and no later than the requested expiry, SHALL be short-lived, scoped to the authorized asset operation, delivered only through authenticated encrypted transport such as HTTPS, and marked to prevent caching and referrer propagation. Access handling SHALL reject insecure or adapter-unapproved destinations and SHALL prevent storage credentials from being disclosed to them, including through redirects. Ordinary Assets registration SHALL validate upload access before creating a pending Asset. Access to an already-committed task-owned Asset SHALL apply the same descriptor validation; failure SHALL return no descriptor or credentials and preserve the existing record, ownership, and lifecycle state. The owning task workflow SHALL retain its existing retry rules and original staging expiry, without deleting/replacing the Asset or extending access merely because descriptor issuance failed.

#### Scenario: Authorized access is short-lived
- **WHEN** an authorized actor requests access to a ready asset
- **THEN** the system returns a time-limited encrypted-transport access descriptor without exposing persistent storage credentials and with no-store/no-referrer handling

#### Scenario: Insecure access descriptor is rejected
- **WHEN** an adapter returns a credential-bearing descriptor that uses cleartext transport or an unapproved destination
- **THEN** the system rejects the descriptor without returning credentials or changing asset state

#### Scenario: Direct endpoints prevent redirect credential leakage
- **WHEN** a storage adapter is configured
- **THEN** its provider configuration guarantees that descriptor endpoints cannot redirect; a provider unable to guarantee direct endpoints is unsupported

#### Scenario: Malformed descriptor headers are rejected
- **WHEN** ordinary Assets registration receives adapter headers other than pairs of nonempty UTF-8 string names and UTF-8 string values
- **THEN** access fails before a pending registration is persisted

#### Scenario: Storage adapter failure is contained
- **WHEN** the configured storage adapter cannot produce authorized access
- **THEN** the action fails without changing asset ownership, readiness, or content identity

#### Scenario: Invalid access preserves an existing task-owned registration
- **WHEN** access issuance for an already-committed task-owned pending Asset receives malformed or insecure descriptor data
- **THEN** the descriptor and credentials are not returned, the same Asset and task ownership remain pending, and the owning workflow may retry under its existing authorization and expiry rules without a replacement Asset or an expiry extension

### Requirement: Attempt-scoped source-asset access
An eligible owner of an unexpired live attempt in an active or paused project SHALL be able to request access only to a ready source asset in that attempt's bound values. The operation SHALL explicitly check active account/organization, current audience route, absence of a block, ownership, and the exact source relationship without requiring organization membership or general asset capability. Descriptors SHALL expire no later than the earlier of five minutes or the attempt deadline, retain the existing encrypted-transport/no-store/no-referrer rules, and grant no persistent storage credentials or general asset browsing. Revocation SHALL deny new descriptor issuance; previously issued descriptors SHALL not be claimed to be retroactively revoked. Existing opaque-download delivery SHALL remain in force until separately scoped media support explicitly permits a supported rendering path.

#### Scenario: An external worker downloads an allocated asset
- **WHEN** an eligible attempt owner requests a ready asset referenced by its bound source values
- **THEN** it receives a short-lived descriptor only for that asset and operation

#### Scenario: An unrelated asset belongs to the same organization
- **WHEN** the worker requests an asset absent from its allocated bound values
- **THEN** access is denied without revealing its metadata or location

### Requirement: Result-scoped source-asset access
An active member authorized for `tasks.results.read` in an active organization and explicit project scope SHALL be able to inspect immutable source-asset metadata and request opaque access only for ready assets bound to TaskInputs referenced by eligible result evidence. This Tasks operation SHALL not require `assets.read`, grant general asset browsing, or authorize unbound/unissued source access. It SHALL recheck result authority at issuance, cap descriptor lifetime at five minutes, and preserve the existing encrypted-transport, no-store/no-referrer, and opaque-download restrictions. Historical exports SHALL contain immutable asset references rather than credentials, bytes, or temporary access URLs.

#### Scenario: A result-only reader downloads a referenced input
- **WHEN** an authorized result reader requests an asset from an issued result's bound input without general asset permission
- **THEN** Tasks issues scoped opaque access for that source, while an unrelated same-organization asset remains denied

### Requirement: Backend export publication uses immutable asset storage
The storage boundary SHALL support server-side streaming staging writes for generated task exports or explicitly return `export_storage_unavailable`. Export publication SHALL preserve provider-enforced byte caps and existing hash/size verification and immutable canonical sealing. It SHALL associate one ready artifact with its export only after successful completion, with no partial-content download. A missing server-write capability SHALL not break existing client upload operations. Provider-neutral contract tests SHALL not claim that an in-memory adapter supplies reachable HTTP endpoints.

#### Scenario: The configured adapter cannot write export staging
- **WHEN** an export needs server-side staging and that capability is unavailable
- **THEN** the export fails explicitly with no ready artifact while ordinary supported asset operations remain available

### Requirement: Task-result assets retain result access scope
Access to an export's artifact through task results SHALL require the existing active account/organization/membership checks and `tasks.results.read`, including after the project is completed or archived. Generic asset reads, access, registration, and canonical-reuse operations SHALL not bypass that requirement for task-generated content solely owned through export relationships. Task-generated assets SHALL carry their export relationship from registration onward, including pending publication. A separate independently authorized source-asset relationship or independently verified upload of identical bytes can grant byte access but SHALL not disclose the export association or its evidence; supplying a hash alone SHALL not establish independent authority. Descriptors SHALL preserve existing short-lived opaque-download restrictions and SHALL never expose storage credentials.

#### Scenario: An asset identifier is used to bypass result permission
- **WHEN** a caller lacking results permission requests an export-only asset through a generic asset read/access operation
- **THEN** access is denied even if the caller has general asset-read permission

#### Scenario: A result reader downloads an artifact
- **WHEN** an authorized results reader requests the ready artifact of a scoped export
- **THEN** the system returns compliant short-lived access without requiring an unrelated asset-management grant

#### Scenario: Hash-only registration cannot unlock protected results
- **WHEN** an actor without result authority supplies the known hash of an export-only asset to a generic registration or reuse operation
- **THEN** that operation does not return the protected canonical asset or establish read access merely from the supplied hash

### Requirement: Upload access describes the actual HTTP request
Upload descriptors SHALL support raw PUT and multipart-form POST requests. Every descriptor SHALL identify its method, exact approved HTTPS destination, expiration, byte cap, and string-valued request headers. A POST descriptor SHALL additionally contain the required string-valued form fields and the name of the file form field. Every fixed object-header or metadata condition in the signed POST policy SHALL have its matching name/value in `form_fields`; policy conditions alone SHALL NOT substitute for submitted fields. Object Content-Type SHALL be a form field, leaving the multipart request Content-Type and boundary to the client's encoder. The signed policy SHALL fix the staging key, bound the permitted content size by the registered byte size, and expire no later than the requested access lifetime. It SHALL NOT allow caller-selected destinations, key prefixes, or success redirects. Clients SHALL submit the fields unchanged and let their HTTP client construct the multipart boundary; a raw PUT descriptor SHALL not carry POST form fields. GET download descriptors SHALL retain their existing representation and SHALL not carry upload fields. Ordinary registration SHALL validate the complete method-specific descriptor before persisting an Asset, while invalid access issuance for an existing task-owned Asset SHALL preserve its identity and lifecycle under the existing retry rules.

#### Scenario: A client receives a POST upload
- **WHEN** authorized registration returns multipart-form POST access
- **THEN** the client can upload using only the descriptor and its file bytes, and the receiving service enforces the signed destination, size, and expiry conditions

#### Scenario: A client omits or changes a fixed POST field
- **WHEN** a client removes or changes a fixed object-header or metadata field required by the signed policy
- **THEN** the receiver rejects the upload instead of relying on unstated client defaults

#### Scenario: An existing adapter returns PUT access
- **WHEN** authorized registration returns a valid raw PUT descriptor
- **THEN** the client can continue uploading the file body with the returned headers without multipart encoding

#### Scenario: A POST descriptor is malformed
- **WHEN** upload access has missing or non-string form values, no file field, an unsupported method, or an invalid destination or expiry
- **THEN** no descriptor or credentials are exposed, ordinary registration creates no Asset, and an existing task-owned registration retains its original identity and state

#### Scenario: An upload policy is modified
- **WHEN** a client changes its signed policy to extend expiry, select another key, or increase the byte cap
- **THEN** the receiving storage service rejects the request without granting canonical-content access
