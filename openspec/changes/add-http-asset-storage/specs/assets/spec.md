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
