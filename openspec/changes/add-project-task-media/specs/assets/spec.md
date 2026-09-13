## ADDED Requirements

### Requirement: Attempt-scoped mask registration and attachment
A live eligible attempt owner SHALL be able to register/finalize an organization-owned mask asset only through a response workflow identifying an offered raster-mask question. The workflow SHALL preserve the existing enforced upload cap, exact hash/size/media identity, immutable sealing, and canonical deduplication rules and record explicit attempt/question ownership. Pending registration links SHALL preserve ownership and result-access scope while authorizing only scoped upload/finalization work, never attachment, download, or rendering. Worker attachment and content access SHALL require successful finalization of that registration's verified upload plus the existing lease, authorization, and applicable media checks. Registration SHALL require a caller-generated UUID request key unique within attempt/question: identical retries SHALL reuse the same registration and return its state-specific outcome defined below, while changed hash/size/media arguments SHALL return `idempotency_conflict`. Same-key retries SHALL not create additional writable objects or extend access beyond the original staging expiry or attempt lease.

Registration SHALL serialize under the core Project/Task/Attempt/Response lock order, recheck current owner/eligibility/lease/state after locking, and atomically persist the UUID key, registration identity, and a new pending Asset with its reserved staging identity before storage I/O. Every new key SHALL require verification of its own uploaded bytes even when a matching canonical asset exists; a supplied hash or asset ID SHALL not grant attachment authority. Successful finalization SHALL establish authority only for this registration's offered attempt/question and resolve canonical ready content under the existing deduplication rules. Same-key retries SHALL retain that canonical resolution. Finalization SHALL neither replace response children nor revoke other finalized registrations for that question. Registration records SHALL preserve provenance and attachment eligibility; current answer membership SHALL come only from MaskRegion children selected by the revision-checked whole-question save, with submitted membership immutable. Rejected registration SHALL create no key reservation, Asset, or writable staging object. Storage I/O SHALL remain outside the database transaction. No task-specific registration-count, aggregate-byte allowance, quota accounting, or automatic staging-deletion prerequisite SHALL be introduced; existing per-file Assets/provider behavior SHALL remain in force.

After current authorization and the core mutation locks, registration SHALL look up the attempt/question UUID request key. An existing key SHALL resolve its matching registration; changed arguments SHALL return `idempotency_conflict`. For an absent key, validate declared facts and check existing canonical identity before creating the registration. An existing canonical hash with a different byte size or media type SHALL return `asset_identity_conflict` without reserving the key or creating a registration, Asset, or staging object. Once registered, calls SHALL use the linked Asset rather than rerunning general asset registration. A canonical asset appearing after that check SHALL be handled by finalizing the already-persisted pending Asset under the existing deduplication/conflict rules. Retry convergence SHALL not bypass current authorization or renew expired storage access.

An admitted registration SHALL follow the existing Assets lifecycle. It SHALL become terminally failed when Assets commits `content_mismatch` or `asset_identity_conflict`, and its expired outcome SHALL correspond to Assets committing failed `staging_expired`. Those transitions SHALL retain the existing asset lock, finalizer-claim, and staging-expiry checks. Transport errors, storage timeouts, missing staging, and interrupted requests SHALL leave the registration pending unless a terminal Assets outcome has committed; retries SHALL respect the existing finalizer claim. Ready and `duplicate_content` outcomes SHALL resolve the canonical ready asset, including after a lost success response.

An identical retry of a pending registration SHALL resume interrupted storage work against its reserved identity/destination under the existing sealing rules while its original staging access remains valid. An existing terminal failed or expired registration SHALL return its recorded outcome without new upload access or revival. Retrying the upload after terminal failure/expiry SHALL require a fresh UUID key and current attempt authorization. Ready and deduplicated registrations SHALL retain their existing canonical-asset resolution.

The workflow SHALL not require membership or expose general asset creation/listing/reuse operations. A duplicate canonical asset SHALL remain usable only through an authorized attachment relationship; failed/foreign/mismatched uploads SHALL not create usable response attachment authority. Verification of raster encoding and dimensions SHALL belong to the separate media prerequisite, not opaque asset finalization.

#### Scenario: A pending mask has ownership without content access
- **WHEN** an attempt owner tries to attach, download, or render its pending mask through the registration link
- **THEN** access is denied even when the declared hash matches ready canonical content; only authorized upload/finalization work is permitted until its own upload has been verified and finalized

#### Scenario: Canonical mask content is reused safely
- **WHEN** a worker's correctly finalized mask deduplicates to identical canonical bytes
- **THEN** that worker can attach it through the specific authorized question link without receiving unrelated asset or response metadata

#### Scenario: A matching canonical asset does not authorize a new mask
- **WHEN** a worker submits a new key with the hash and declared facts of an existing canonical mask
- **THEN** admission creates a pending Asset and grants no ready-mask attachment or download access until that registration's upload is verified; successful deduplication authorizes only its offered attempt/question, and later same-key retries require no new upload

#### Scenario: A lease expires during upload
- **WHEN** the worker requests finalization or attachment after its lease has ended
- **THEN** the response workflow denies the operation and does not revive the attempt or create a submitted answer

#### Scenario: Concurrent retries register one mask
- **WHEN** two requests supply the same attempt/question/key and identical content identity
- **THEN** they converge on one registration and any required staging uses one reserved destination; conflicting content under that key is rejected

#### Scenario: A known canonical identity conflicts before admission
- **WHEN** a new mask key names an existing canonical hash with a different byte size or media type
- **THEN** registration returns `asset_identity_conflict` without admitting the key or creating an Asset or staging object

#### Scenario: A conflicting canonical asset appears after admission
- **WHEN** a mask registration has persisted its pending Asset and another upload publishes the same hash with a different declared media type before mask finalization
- **THEN** finalization records `asset_identity_conflict` on the admitted Asset, and identical mask retries return that terminal outcome without creating another registration

#### Scenario: A pending upload resumes after interrupted storage work
- **WHEN** storage work is interrupted after registration and its live eligible owner retries the same UUID key and arguments while staging access remains valid
- **THEN** storage work resumes against the reserved identity/destination without another registration or expiry extension

#### Scenario: A transient storage error leaves an upload pending
- **WHEN** a timeout or missing staging interrupts an admitted upload and no terminal Assets outcome has committed
- **THEN** it remains pending, and a same-key retry can resume subject to the existing finalizer claim and staging expiry without creating another registration

#### Scenario: Assets commits a terminal upload failure
- **WHEN** Assets commits `content_mismatch`, `asset_identity_conflict`, or failed `staging_expired` under its existing lifecycle checks
- **THEN** the registration returns that failed or expired outcome on identical retries and cannot obtain renewed upload access

#### Scenario: A terminal upload failure requires a new key
- **WHEN** a live eligible owner retries a failed or expired registration with identical arguments
- **THEN** the original terminal outcome is returned without upload access, and a replacement upload requires a fresh UUID key and current attempt authorization while retaining the old registration as history

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
