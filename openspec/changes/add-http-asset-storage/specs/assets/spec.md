## ADDED Requirements

### Requirement: Upload access describes the actual HTTP request
Upload descriptors SHALL support raw PUT and multipart-form POST requests. Every descriptor SHALL identify its method, exact approved HTTPS destination, expiration, byte cap, and string-valued request headers. A POST descriptor SHALL additionally contain the required string-valued form fields and the name of the file form field. The signed policy SHALL fix the staging key, bound the permitted content size by the registered byte size, and expire no later than the requested access lifetime. It SHALL NOT allow caller-selected destinations, key prefixes, or success redirects. Clients SHALL submit the fields unchanged and let their HTTP client construct the multipart boundary; a raw PUT descriptor SHALL not carry POST form fields. GET download descriptors SHALL retain their existing representation and SHALL not carry upload fields. Ordinary registration SHALL validate the complete method-specific descriptor before persisting an Asset, while invalid access issuance for an existing task-owned Asset SHALL preserve its identity and lifecycle under the existing retry rules.

#### Scenario: A client receives a POST upload
- **WHEN** authorized registration returns multipart-form POST access
- **THEN** the client can upload using only the descriptor and its file bytes, and the receiving service enforces the signed destination, size, and expiry conditions

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

### Requirement: Opaque download delivery
The system SHALL serve ready assets only as downloads. HTTP storage adapters SHALL enforce response headers `Content-Disposition: attachment`, `Content-Type: application/octet-stream`, and `Cache-Control: no-store` through provider metadata or authenticated response overrides. Download access SHALL target an approved HTTPS storage hostname distinct from application hostnames and outside the scope of application session cookies. Application cookies and bearer credentials SHALL NOT be sent to storage; the issued operation-scoped storage authorization SHALL authorize the transfer. Clients SHALL treat these URLs only as file-transfer access and SHALL NOT load them as scripts, stylesheets, or inline application content. An otherwise-compliant isolated download endpoint SHALL remain supported without `X-Content-Type-Options: nosniff`; where a delivery endpoint supplies that header, the system SHALL retain it. Attachment disposition, binary content type, and origin isolation SHALL NOT be represented as equivalent to nosniff's script/style MIME enforcement. Request headers in an access descriptor SHALL NOT be considered enforcement of response headers. Inline previews and image dimensions are deferred; existing nullable dimension fields SHALL remain unset on newly finalized assets.

#### Scenario: Declared media type does not control rendering
- **WHEN** an authorized client downloads an asset declared as HTML, PDF, or an image
- **THEN** the provider responds with attachment disposition, octet-stream content type, and no-store from the isolated storage host, independently of the declared media type

#### Scenario: Direct storage cannot set nosniff
- **WHEN** the configured direct storage endpoint enforces the mandatory download headers and isolation but cannot add nosniff
- **THEN** the adapter remains eligible and issues short-lived download access without requiring an application streaming route or a header-injection proxy

#### Scenario: Storage overlaps application credentials
- **WHEN** a proposed download destination shares an application hostname or falls within an application session cookie's scope
- **THEN** that deployment does not qualify for direct download delivery until the storage hostname and cookie scope are isolated
