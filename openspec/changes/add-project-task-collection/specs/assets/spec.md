## ADDED Requirements

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
The storage boundary SHALL support bounded server-side staging writes for generated task exports or explicitly return `export_storage_unavailable`. Export publication SHALL preserve provider-enforced byte caps and existing hash/size verification and immutable canonical sealing. It SHALL associate one ready artifact with its export only after successful completion, with no partial-content download. A missing server-write capability SHALL not break existing client upload operations. Provider-neutral contract tests SHALL not claim that an in-memory adapter supplies reachable HTTP endpoints.

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
