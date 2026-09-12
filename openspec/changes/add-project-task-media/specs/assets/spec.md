## ADDED Requirements

### Requirement: Attempt-scoped mask registration and attachment
A live eligible attempt owner SHALL be able to register/finalize an organization-owned mask asset only through a response workflow identifying an offered raster-mask question. The workflow SHALL preserve the existing enforced upload cap, exact hash/size/media identity, immutable sealing, and canonical deduplication rules and record explicit attempt/question attachment authority. Registration SHALL require a 1–128 byte request key unique within attempt/question: identical retries SHALL resolve to the same registration, asset, and staging destination, while changed hash/size/media arguments SHALL return `idempotency_conflict`. Retries SHALL not create additional writable objects or extend access beyond the original staging expiry or attempt lease.

New registrations SHALL be limited over the entire attempt lifetime to 1,000 per question, 10,000 across all questions, and 256 MiB of aggregate declared bytes, alongside the existing per-file byte cap. Pending, ready, failed, expired, deduplicated, and replaced registrations SHALL all consume these limits; detaching a draft mask SHALL not refund allowance. Admission SHALL serialize under the existing Response lock and durably reserve the key, registration identity, count, and byte allowance before any storage operation. Limit failures SHALL return `mask_registration_limit` without allocating an asset or writable staging object. Storage I/O SHALL remain outside the database transaction and retry the reserved identity/destination. These are local attempt limits; no generic quota service or automatic staging-deletion prerequisite SHALL be introduced.

After current owner/eligibility/lease authorization and under the Response lock, registration SHALL look up the attempt/question request key before checking remaining allowance. An existing key SHALL resolve its matching registration without consuming additional count or bytes even when a limit is reached; changed arguments SHALL return `idempotency_conflict` rather than a limit error. Existing failed or expired registrations SHALL retain their state and original expiry. Only an absent key SHALL be checked against the limits and reserve new allowance; retry convergence SHALL not bypass current authorization or renew expired storage access.

The workflow SHALL not require membership or expose general asset creation/listing/reuse operations. A duplicate canonical asset SHALL remain usable only through an authorized attachment relationship; failed/foreign/mismatched uploads SHALL not create usable response attachment authority. Verification of raster encoding and dimensions SHALL belong to the separate media prerequisite, not opaque asset finalization.

#### Scenario: Canonical mask content is reused safely
- **WHEN** a worker's correctly finalized mask deduplicates to identical canonical bytes
- **THEN** that worker can attach it through the specific authorized question link without receiving unrelated asset or response metadata

#### Scenario: A lease expires during upload
- **WHEN** the worker requests finalization or attachment after its lease has ended
- **THEN** the response workflow denies the operation and does not revive the attempt or create a submitted answer

#### Scenario: Concurrent retries register one mask
- **WHEN** two requests supply the same attempt/question/key and identical content identity
- **THEN** they converge on one registration and staging destination, consume allowance once, and conflicting content under that key is rejected

#### Scenario: A matching retry arrives at the limit
- **WHEN** an authorized live attempt is at a registration count or byte limit and retries an existing key with identical arguments
- **THEN** it resolves the existing registration without consuming allowance or extending expiry, while changed arguments under that key conflict and a new key fails with `mask_registration_limit`

#### Scenario: Completed or abandoned uploads cannot evade the limit
- **WHEN** a worker registers more masks after earlier uploads are finalized, failed, expired, deduplicated, or detached
- **THEN** all previous registrations still count toward the lifetime count/byte limits, and a request exceeding either limit creates no additional asset or staging object

#### Scenario: Distinct requests race for the remaining allowance
- **WHEN** concurrent new keys would together exceed the remaining registration count or declared-byte allowance
- **THEN** admission commits only requests that fit the shared limits before storage access is issued, and retries after interrupted storage work reuse the reserved identities

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
