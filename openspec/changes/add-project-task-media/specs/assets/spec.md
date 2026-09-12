## ADDED Requirements

### Requirement: Attempt-scoped mask registration and attachment
A live eligible attempt owner SHALL be able to register/finalize an organization-owned mask asset only through a response workflow identifying an offered raster-mask question. The workflow SHALL preserve the existing enforced upload cap, exact hash/size/media identity, immutable sealing, and canonical deduplication rules and record explicit attempt/question attachment authority. Registration SHALL require a 1–128 byte request key unique within attempt/question: identical retries SHALL reuse the same registration and return its state-specific outcome defined below, while changed hash/size/media arguments SHALL return `idempotency_conflict`. Same-key retries SHALL not create additional writable objects or extend access beyond the original staging expiry or attempt lease.

New registrations SHALL be limited over the entire attempt lifetime to 1,000 per question, 10,000 across all questions, and 256 MiB of aggregate declared bytes, alongside the existing per-file byte cap. Pending, ready, failed, expired, deduplicated, and replaced registrations SHALL all consume these limits; detaching a draft mask SHALL not refund allowance. Admission SHALL serialize under the existing Response lock and atomically persist the key, registration identity, count/byte allowance, and either a link to an independently authorized matching canonical ready asset or a pending Asset with its reserved staging identity, before any storage operation. Limit violations SHALL return `mask_registration_limit`. Rejected admission SHALL create no registration or key reservation, consume no allowance, and allocate no asset or writable staging object. Storage I/O SHALL remain outside the database transaction. These are local attempt limits; no generic quota service or automatic staging-deletion prerequisite SHALL be introduced.

After current owner/eligibility/lease authorization and under the Response lock, registration SHALL look up the attempt/question request key before checking remaining allowance. An existing key SHALL resolve its matching registration without consuming additional count or bytes even when a limit is reached; changed arguments SHALL return `idempotency_conflict` rather than a limit error. For an absent key, validate declared facts and check existing canonical identity before checking limits or committing admission. An existing canonical hash with a different byte size or media type SHALL return `asset_identity_conflict` without reserving the key, creating a registration or Asset, consuming allowance, or allocating storage. Once admitted, calls SHALL use the linked Asset rather than rerunning general asset registration. A canonical asset appearing after that check SHALL be handled by finalizing the already-persisted pending Asset under the existing deduplication/conflict rules. Retry convergence SHALL not bypass current authorization or renew expired storage access.

An admitted registration SHALL follow the existing Assets lifecycle. It SHALL become terminally failed when Assets commits `content_mismatch` or `asset_identity_conflict`, and its expired outcome SHALL correspond to Assets committing failed `staging_expired`. Those transitions SHALL retain the existing asset lock, finalizer-claim, and staging-expiry checks. Transport errors, storage timeouts, missing staging, and interrupted requests SHALL leave the registration pending unless a terminal Assets outcome has committed; retries SHALL respect the existing finalizer claim. Ready and `duplicate_content` outcomes SHALL resolve the canonical ready asset, including after a lost success response.

An identical retry of a pending registration SHALL resume interrupted storage work against its reserved identity/destination under the existing sealing rules while its original staging access remains valid, without additional allowance even at a limit. An existing terminal failed or expired registration SHALL return its recorded terminal outcome without new upload access or revival. Retrying the upload after terminal failure/expiry SHALL require a fresh key, current attempt authorization, and remaining count/byte allowance; the old registration SHALL not be refunded. An otherwise admissible replacement with insufficient remaining allowance SHALL fail with `mask_registration_limit`. Ready and deduplicated registrations SHALL retain their existing canonical-asset resolution.

The workflow SHALL not require membership or expose general asset creation/listing/reuse operations. A duplicate canonical asset SHALL remain usable only through an authorized attachment relationship; failed/foreign/mismatched uploads SHALL not create usable response attachment authority. Verification of raster encoding and dimensions SHALL belong to the separate media prerequisite, not opaque asset finalization.

#### Scenario: Canonical mask content is reused safely
- **WHEN** a worker's correctly finalized mask deduplicates to identical canonical bytes
- **THEN** that worker can attach it through the specific authorized question link without receiving unrelated asset or response metadata

#### Scenario: A lease expires during upload
- **WHEN** the worker requests finalization or attachment after its lease has ended
- **THEN** the response workflow denies the operation and does not revive the attempt or create a submitted answer

#### Scenario: Concurrent retries register one mask
- **WHEN** two requests supply the same attempt/question/key and identical content identity
- **THEN** they converge on one registration, consume allowance once, and any required staging uses one reserved destination; conflicting content under that key is rejected

#### Scenario: A known canonical identity conflicts before admission
- **WHEN** a new mask key names an existing canonical hash with a different byte size or media type
- **THEN** registration returns `asset_identity_conflict` without admitting the key, consuming allowance, or creating an Asset or staging object

#### Scenario: A conflicting canonical asset appears after admission
- **WHEN** a mask registration has persisted its pending Asset and another upload publishes the same hash with a different declared media type before mask finalization
- **THEN** finalization records `asset_identity_conflict` on the admitted Asset, and identical mask retries return that terminal outcome without a second admission or allowance debit

#### Scenario: A matching retry arrives at the limit
- **WHEN** an authorized live attempt is at a registration count or byte limit and retries an existing key with identical arguments
- **THEN** it resolves the existing registration without consuming allowance or extending expiry, while changed arguments under that key conflict and an otherwise valid new key fails with `mask_registration_limit`

#### Scenario: Completed or abandoned uploads cannot evade the limit
- **WHEN** a worker registers more masks after earlier uploads are finalized, failed, expired, deduplicated, or detached
- **THEN** all previous registrations still count toward the lifetime count/byte limits, and a request exceeding either limit creates no additional asset or staging object

#### Scenario: Distinct requests race for the remaining allowance
- **WHEN** concurrent new keys would together exceed the remaining registration count or declared-byte allowance
- **THEN** admission commits only requests that fit the shared limits before storage access is issued, and retries of still-pending registrations after interrupted storage work reuse the reserved identities

#### Scenario: A pending upload resumes at the allowance limit
- **WHEN** storage work is interrupted after a registration has reserved the last available allowance and its live eligible owner retries the same key and arguments while the registration is pending and staging access remains valid
- **THEN** storage work resumes against the reserved identity/destination under the existing sealing rules without another allowance debit or expiry extension

#### Scenario: A transient storage error leaves an upload pending
- **WHEN** a timeout or missing staging interrupts an admitted upload and no terminal Assets outcome has committed
- **THEN** it remains pending, and a same-key retry can resume subject to the existing finalizer claim and staging expiry without consuming new allowance

#### Scenario: Assets commits a terminal upload failure
- **WHEN** Assets commits `content_mismatch`, `asset_identity_conflict`, or failed `staging_expired` under its existing lifecycle checks
- **THEN** the registration returns that failed or expired outcome on identical retries and cannot obtain renewed upload access

#### Scenario: A terminal upload failure requires a new key
- **WHEN** a live eligible owner retries a failed or expired registration with identical arguments
- **THEN** the original terminal outcome is returned without upload access, and a replacement upload requires a fresh key and sufficient remaining allowance without refunding the old registration; an otherwise admissible new key at exhausted allowance fails with `mask_registration_limit`

#### Scenario: A rejected admission consumes no registration allowance
- **WHEN** an otherwise valid new request exceeds remaining allowance
- **THEN** it fails with `mask_registration_limit` without reserving its key, creating a registration or asset, consuming allowance, or allocating writable staging

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
