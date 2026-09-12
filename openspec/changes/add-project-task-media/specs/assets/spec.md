## ADDED Requirements

### Requirement: Attempt-scoped mask registration and attachment
A live eligible attempt owner SHALL be able to register/finalize an organization-owned mask asset only through a response workflow identifying an offered raster-mask question. The workflow SHALL preserve the existing enforced upload cap, exact hash/size/media identity, immutable sealing, and canonical deduplication rules and record explicit attempt/question attachment authority. It SHALL not require membership or expose general asset creation/listing/reuse operations. A duplicate canonical asset SHALL remain usable only through an authorized attachment relationship; failed/foreign/mismatched uploads SHALL not create response attachment authority. Verification of raster encoding and dimensions SHALL belong to the separate media prerequisite, not opaque asset finalization.

#### Scenario: Canonical mask content is reused safely
- **WHEN** a worker's correctly finalized mask deduplicates to identical canonical bytes
- **THEN** that worker can attach it through the specific authorized question link without receiving unrelated asset or response metadata

#### Scenario: A lease expires during upload
- **WHEN** the worker requests finalization or attachment after its lease has ended
- **THEN** the response workflow denies the operation and does not revive the attempt or create a submitted answer

## MODIFIED Requirements

### Requirement: Task-result assets retain result access scope
Access to an export's artifact or a response-mask attachment through task results SHALL require the existing active account/organization/membership checks and `tasks.results.read`, including after the project is completed or archived. Generic asset reads, access, registration, and canonical-reuse operations SHALL not bypass that requirement for task-generated content solely owned through result/response relationships. Task-generated assets SHALL carry their attempt/export relationship from registration onward, including pending publication. A separate independently authorized source-asset relationship or independently verified upload of identical bytes can grant byte access but SHALL not disclose the export/response association or its evidence; supplying a hash alone SHALL not establish independent authority. Worker attachment authority SHALL be limited to its live attempt. Descriptors SHALL preserve existing short-lived opaque-download restrictions and SHALL never expose storage credentials.

#### Scenario: An asset identifier is used to bypass result permission
- **WHEN** a caller lacking results permission requests an export-only asset through a generic asset read/access operation
- **THEN** access is denied even if the caller has general asset-read permission

#### Scenario: A result reader downloads an artifact
- **WHEN** an authorized results reader requests the ready artifact of a scoped export
- **THEN** the system returns compliant short-lived access without requiring an unrelated asset-management grant

#### Scenario: Hash-only registration cannot unlock protected results
- **WHEN** an actor without result authority supplies the known hash of an export-only asset to a generic registration or reuse operation
- **THEN** that operation does not return the protected canonical asset or establish read access merely from the supplied hash
