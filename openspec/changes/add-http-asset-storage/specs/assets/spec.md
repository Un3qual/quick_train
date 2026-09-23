## ADDED Requirements

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

## MODIFIED Requirements

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
