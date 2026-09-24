# http-asset-storage Specification

## Purpose

Make asset uploads, immutable file downloads, and task export transfers usable over HTTPS through S3, with a local development and verification environment that requires no live cloud services.

## Requirements

### Requirement: Local and production storage share the same protocol implementation
The system SHALL support AWS S3 in production and VersityGW in local development and integration tests through the same S3 storage implementation. Endpoint, region, addressing style, bucket, credentials, and certificate trust SHALL be deployment configuration. Production AWS endpoints SHALL be regional HTTPS endpoints; local VersityGW SHALL use its explicitly configured HTTPS endpoint. Both SHALL validate certificates and hostnames and reject redirects. Ordinary tests SHALL retain the existing in-memory storage implementation. Local and test configuration SHALL use explicit local endpoints and local-only credentials, SHALL NOT discover AWS credentials or fall back to AWS endpoints, and SHALL NOT contact cloud metadata services. Missing or invalid production storage configuration SHALL fail closed rather than fall back to local storage or a test double.

#### Scenario: Development runs without AWS configuration
- **WHEN** a developer starts the documented local services and performs an asset upload and download
- **THEN** the transfer uses local VersityGW and requires no AWS account, AWS credentials, or reachable AWS service

#### Scenario: Local storage is unavailable
- **WHEN** the configured local endpoint cannot be reached
- **THEN** storage operations fail explicitly without contacting a default AWS endpoint or using ambient cloud credentials

#### Scenario: A local endpoint is not an AWS regional endpoint
- **WHEN** the configured VersityGW endpoint has a valid trusted HTTPS identity and serves requests without redirects
- **THEN** local configuration accepts it without requiring an AWS regional hostname

### Requirement: Uploads are capped by the receiving service
Client upload access SHALL bind an exact private staging key, expiration, and a byte-size limit no larger than the registered asset size. S3 POST descriptors and policies SHALL omit ACL fields/conditions, and backend PUTs SHALL omit ACL headers. Production AWS qualification SHALL require Bucket owner enforced Object Ownership, Block Public Access, and bucket/identity policies restricting access to required authenticated operations; an explicit `acl: private` SHALL NOT be the privacy mechanism. Local VersityGW SHALL enforce private bucket access using the same ACL-free upload requests without requiring AWS ownership-control APIs. Local and deployment checks SHALL verify signed upload success and rejection of unsigned object reads/writes. The receiving service SHALL enforce the cap independently of the client and of later finalization. Altering the destination, extending the expiration, or weakening the size condition SHALL invalidate access. Successful upload SHALL NOT itself make an asset ready or grant download access. Access SHALL never permit writes to canonical published content.

#### Scenario: Production uploads use a bucket with ACLs disabled
- **WHEN** a client submits only the issued POST descriptor and file to the qualified production bucket using Bucket owner enforced ownership
- **THEN** the upload succeeds without an ACL field and the object remains inaccessible to unsigned reads or writes

#### Scenario: A client exceeds its registered size
- **WHEN** a client uploads more bytes than its issued access permits
- **THEN** the receiving service rejects the upload and the asset remains unavailable for download

#### Scenario: Multipart framing exceeds the file-size cap
- **WHEN** a valid multipart POST contains file bytes exactly equal to the registered size plus the required form fields and framing
- **THEN** the receiving service accepts the upload because the cap applies to file bytes, while one additional file byte is rejected

#### Scenario: A client modifies its upload authorization
- **WHEN** the client changes the permitted key, expiry, or size conditions
- **THEN** the storage service rejects the modified authorization

### Requirement: Publication verifies one stable source and an immutable destination
Finalization SHALL select a stable staging object version, verify its actual complete byte size and SHA-256, and publish only those verified bytes at the existing organization-scoped canonical location. The publication SHALL conditionally create that location and SHALL NOT overwrite existing canonical bytes. Existing canonical content SHALL be reused only after verifying its complete bytes and immutable declared facts. Canonical metadata SHALL represent the exact persisted declared media type with a fixed-size SHA-256 digest, independently of the download Content-Type, preserving currently valid long and non-ASCII media-type values without imposing a new registration limit. Verification SHALL reject a missing, malformed, or mismatched digest and SHALL still verify complete content bytes. A staging overwrite during verification SHALL NOT change the selected version or the content later served. A mismatched upload SHALL NOT occupy a canonical location, even when another registration has matching canonical content. Network I/O SHALL NOT hold asset database transactions open; existing finalizer claim checks SHALL govern readiness transitions.

#### Scenario: Staging changes during publication
- **WHEN** an upload replaces the current staging object while a finalizer verifies an earlier version
- **THEN** finalization publishes that verified version or fails, and never combines facts from one version with bytes from another

#### Scenario: Identical finalizers race
- **WHEN** two registrations concurrently publish matching verified bytes to the same organization-scoped canonical location
- **THEN** they converge on one immutable object and the existing canonical asset resolution without replacement or per-registration sealed copies

#### Scenario: A valid declared media type exceeds the provider metadata budget
- **WHEN** an otherwise-valid asset has a long or non-ASCII declared media type whose direct encoding would exceed S3 metadata limits
- **THEN** publication stores its fixed-size digest, preserves the exact database value, and can verify and reuse the canonical object without a metadata-size failure

#### Scenario: Canonical content has a different declared media type
- **WHEN** canonical bytes match but their declared-media-type digest differs from the expected asset fact
- **THEN** finalization reports a conflict without overwriting or adopting the canonical object

### Requirement: Bounded remote operations preserve honest retry outcomes
Storage operations SHALL return within their configured operation deadline, release local streams and temporary files, and expose only sanitized failures. A timeout or lost response SHALL NOT be treated as proof that the remote service cancelled an already accepted operation. Complete staging or canonical bytes can exist after an uncertain outcome, but no failed or uncertain operation SHALL grant database readiness or download access. Retries SHALL reverify remote content and current lifecycle claims before recording success. Oversized, interrupted, or incomplete source streams SHALL NOT produce publishable partial content. Previously verified canonical objects SHALL remain unchanged by retries.

#### Scenario: The provider commits but its response is lost
- **WHEN** a storage request times out after the provider has accepted complete content
- **THEN** the caller receives a bounded failure without a ready artifact, and retry can verify and adopt the complete content under current claim checks

#### Scenario: A source stream is incomplete
- **WHEN** source enumeration fails, exceeds its byte cap, or misses its deadline
- **THEN** no complete staging object is installed from its partial bytes and no download is issued

### Requirement: Authorized downloads transfer directly from isolated storage
After existing asset, attempt, or result authorization succeeds, the system SHALL issue a short-lived signed GET descriptor for the exact sealed object on the configured isolated storage host. The client SHALL retrieve the bytes directly from S3 or VersityGW. The service SHALL enforce the opaque-download response contract independently of client request headers and of the asset's declared media type. Response settings supplied in a signed URL SHALL be authenticated so changing them cannot authorize inline rendering or a different content type. Canonical object metadata SHALL also carry attachment disposition, octet-stream content type, and no-store. Local and deployment verification SHALL inspect actual transfer responses rather than infer compliance from the descriptor. Nosniff availability SHALL be recorded but SHALL NOT determine qualification for this isolated download path. This change SHALL require neither an application download route nor a CDN/proxy; GraphQL SHALL remain the only application API.

#### Scenario: A client downloads declared HTML
- **WHEN** an authorized client follows access for a sealed asset whose declared media type is HTML
- **THEN** it receives the verified bytes directly from storage with attachment, octet-stream, and no-store response headers, and the absence of nosniff alone does not fail the transfer contract

#### Scenario: A signed download is changed
- **WHEN** a client changes the signed object key, expiry, or any signed response-header override
- **THEN** storage rejects the altered request without serving asset bytes under the modified authorization

#### Scenario: Download access expires
- **WHEN** a client starts a download request after the descriptor's signed expiry
- **THEN** storage denies the request even when the sealed object still exists

### Requirement: Exports use real storage without changing their evidence
The S3 implementation SHALL support streaming backend writes for generated exports within the existing configured asset cap. It SHALL preserve the sealed export membership, deterministic bytes, result ownership, and existing retry/replacement rules. Export download access SHALL still require current result authority at issuance. Failures SHALL not expose a partial artifact, a new snapshot under the same identity, or provider secrets. Generated content SHALL pass the same integrity and canonical-publication checks as client uploads.

#### Scenario: An authorized reader downloads an export
- **WHEN** an export completes against local or production S3 storage and a currently authorized results reader requests it
- **THEN** the reader can retrieve the complete deterministic JSONL bytes through real HTTPS delivery

#### Scenario: Export publication retries
- **WHEN** a generated-content write or publication response is lost
- **THEN** retry preserves the sealed snapshot and converges on its verified content without exposing a partial download

### Requirement: Local storage has persistent development data and disposable test isolation
The documented local storage service SHALL use a pinned stable VersityGW release, local-only credentials, and host ports bound to loopback. Development data SHALL persist across ordinary service restarts. Integration tests SHALL use a distinct storage namespace or instance and SHALL clean only resources allocated to that test run. Concurrent test runs SHALL not overwrite or delete one another's objects. Local HTTPS clients SHALL validate the service identity using an explicitly trusted development certificate; disabling certificate verification SHALL NOT be the default or the integration-test path.

#### Scenario: Restarting development services
- **WHEN** a developer stops and starts the local services without explicitly resetting data
- **THEN** previously uploaded development assets remain stored

#### Scenario: Cleaning integration-test data
- **WHEN** a storage integration run completes or fails
- **THEN** its cleanup cannot delete development objects or another test run's objects

### Requirement: Full verification requires no live cloud storage
The standard test command SHALL run ordinary tests with the in-memory adapter. The full repository verification command SHALL additionally exercise the real S3 adapter against local VersityGW, including HTTPS transfers, actual upload-cap enforcement, invalid/expired authorization, byte verification, immutable publication races, direct downloads with mandatory response headers regardless of declared media type, rejection of modified signed download parameters, storage-host isolation, and export delivery. These commands SHALL require no AWS credentials, cloud storage account, or cloud-provider API access. Toolchain/container-image downloads and existing dependency-audit network access remain separate tooling requirements; this contract does not promise a fully offline verification gate. Failure to start or reach required local integration services SHALL fail the full gate explicitly, rather than silently skip those checks.

#### Scenario: Full verification on a machine without AWS credentials
- **WHEN** dependencies and the pinned local images are available and full verification runs
- **THEN** both ordinary and local storage integration checks execute without cloud API access

#### Scenario: Local integration setup fails
- **WHEN** the required local storage service cannot be started
- **THEN** the full gate reports failure rather than reporting success from the ordinary suite alone

### Requirement: Provider qualification is separate from local compatibility
The change SHALL record which behaviors were verified against the pinned local service. A separately invoked deployment check SHALL inspect and exercise the exact endpoint, region, bucket, and application identity configured for production, including its real permissions, versioning, TLS, upload restrictions, immutable publication, production staging retention, and delivery headers. Configuration inspection SHALL target that same bucket, and application-operation probes SHALL use the runtime application identity. Probe objects SHALL use a unique per-run namespace within the normal staging and sealed key prefixes under the production policies, without qualification-only policy exceptions. Mutation probes and cleanup SHALL affect only that run's objects and versions, never pre-existing objects or bucket configuration. The check SHALL identify its target in its output; a different bucket's results SHALL NOT qualify the runtime bucket. Changes to the target, application identity, or relevant bucket controls SHALL require requalification before enabling access. This check SHALL never run implicitly from development startup, ordinary tests, or full local verification. Passing local checks SHALL NOT be reported as verification of an untested AWS deployment. Local compatibility defects SHALL be resolved or explicitly block qualification; they SHALL NOT be hidden by weakening production invariants or silently replacing approved local storage.

#### Scenario: A deployment has not been checked
- **WHEN** local verification passes but the AWS deployment check has not run
- **THEN** the result reports local compatibility success and AWS deployment verification as not performed

#### Scenario: A deployment uses browser fetch transfers
- **WHEN** a deployment uses browser fetch uploads or downloads
- **THEN** the server-side qualification report identifies browser CORS as not checked, and the operator must separately configure and verify transfers from each actual application origin before enabling browser access

#### Scenario: A different bucket passed qualification
- **WHEN** a disposable bucket passes checks but the configured runtime bucket lacks required versioning, retention, or sealed-object protection
- **THEN** the deployment remains unqualified until checks pass against the runtime bucket and application identity

#### Scenario: Qualification runs alongside existing production data
- **WHEN** the deployment check exercises denied replacement/deletion or cleans its probe objects from the configured bucket
- **THEN** it targets only that run's keys and versions under the normal staging and sealed prefixes, leaving pre-existing objects and bucket configuration unchanged

### Requirement: Production staging retention uses safe native lifecycle rules
Production qualification SHALL require enabled provider-native lifecycle rules scoped to `assets/staging/` that expire current versions, permanently expire noncurrent versions without a retained-version-count exception, and remove expired delete markers. Both current and noncurrent expiration ages SHALL be finite and strictly greater than the sum of configured maximum staging lifetime, upload-access lifetime, publication-claim lifetime, and operation budget. The deployment check SHALL inspect the complete bucket lifecycle configuration and reject rules that can expire or transition sealed objects or shorten that staging safety window. Staging retention settings that block lifecycle expiration SHALL prevent qualification. Operators SHALL provision the documented simple rule configuration; the application SHALL NOT provision lifecycle policies or add a cleanup worker. Local development reset and disposable integration volumes SHALL remain independent of production lifecycle rules. Asynchronous provider cleanup SHALL NOT be presented as an exact deletion deadline, a hard storage quota, or completion of deferred application maintenance.

#### Scenario: Replayed uploads have no complete retention policy
- **WHEN** staging current-version expiration, noncurrent-version expiration, or expired delete-marker cleanup is missing or disabled
- **THEN** the deployment check rejects production qualification rather than accepting indefinite retention of replayed upload versions

#### Scenario: Retention can delete live or sealed bytes
- **WHEN** an expiration age is within the configured staging safety window or an overlapping expiration/transition rule can affect sealed content
- **THEN** production qualification fails even if the application identity itself cannot delete sealed objects

#### Scenario: Staging retention protects active publication
- **WHEN** the complete configuration uses supported staging-only rules with both expiration ages beyond the configured safety window and no expiration blockers
- **THEN** retention qualification succeeds without waiting for asynchronous lifecycle execution or enabling a QuickTrain cleanup worker
