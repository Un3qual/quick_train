## Purpose

Make asset uploads, immutable file downloads, and task export transfers usable over HTTPS through S3, with a local development and verification environment that requires no live cloud services.

## ADDED Requirements

### Requirement: Local and production storage share the same protocol implementation
The system SHALL support AWS S3 in production and VersityGW in local development and integration tests through the same S3 storage implementation. Endpoint, region, addressing style, bucket, credentials, and certificate trust SHALL be deployment configuration. Ordinary tests SHALL retain the existing in-memory storage implementation. Local and test configuration SHALL use explicit local endpoints and local-only credentials, SHALL NOT discover AWS credentials or fall back to AWS endpoints, and SHALL NOT contact cloud metadata services. Missing or invalid production storage configuration SHALL fail closed rather than fall back to local storage or a test double.

#### Scenario: Development runs without AWS configuration
- **WHEN** a developer starts the documented local services and performs an asset upload and download
- **THEN** the transfer uses local VersityGW and requires no AWS account, AWS credentials, or reachable AWS service

#### Scenario: Local storage is unavailable
- **WHEN** the configured local endpoint cannot be reached
- **THEN** storage operations fail explicitly without contacting a default AWS endpoint or using ambient cloud credentials

### Requirement: Uploads are capped by the receiving service
Client upload access SHALL bind an exact private staging key, expiration, and a byte-size limit no larger than the registered asset size. The receiving service SHALL enforce the cap independently of the client and of later finalization. Altering the destination, extending the expiration, or weakening the size condition SHALL invalidate access. Successful upload SHALL NOT itself make an asset ready or grant download access. Access SHALL never permit writes to canonical published content.

#### Scenario: A client exceeds its registered size
- **WHEN** a client uploads more bytes than its issued access permits
- **THEN** the receiving service rejects the upload and the asset remains unavailable for download

#### Scenario: A client modifies its upload authorization
- **WHEN** the client changes the permitted key, expiry, or size conditions
- **THEN** the storage service rejects the modified authorization

### Requirement: Publication verifies one stable source and an immutable destination
Finalization SHALL select a stable staging object version, verify its actual complete byte size and SHA-256, and publish only those verified bytes at the existing organization-scoped canonical location. The publication SHALL conditionally create that location and SHALL NOT overwrite existing canonical bytes. Existing canonical content SHALL be reused only after verifying its complete bytes and immutable declared facts. A staging overwrite during verification SHALL NOT change the selected version or the content later served. A mismatched upload SHALL NOT occupy a canonical location, even when another registration has matching canonical content. Network I/O SHALL NOT hold asset database transactions open; existing finalizer claim checks SHALL govern readiness transitions.

#### Scenario: Staging changes during publication
- **WHEN** an upload replaces the current staging object while a finalizer verifies an earlier version
- **THEN** finalization publishes that verified version or fails, and never combines facts from one version with bytes from another

#### Scenario: Identical finalizers race
- **WHEN** two registrations concurrently publish matching verified bytes to the same organization-scoped canonical location
- **THEN** they converge on one immutable object and the existing canonical asset resolution without replacement or per-registration sealed copies

### Requirement: Bounded remote operations preserve honest retry outcomes
Storage operations SHALL return within their configured operation deadline, release local streams and temporary files, and expose only sanitized failures. A timeout or lost response SHALL NOT be treated as proof that the remote service cancelled an already accepted operation. Complete staging or canonical bytes can exist after an uncertain outcome, but no failed or uncertain operation SHALL grant database readiness or download access. Retries SHALL reverify remote content and current lifecycle claims before recording success. Oversized, interrupted, or incomplete source streams SHALL NOT produce publishable partial content. Previously verified canonical objects SHALL remain unchanged by retries.

#### Scenario: The provider commits but its response is lost
- **WHEN** a storage request times out after the provider has accepted complete content
- **THEN** the caller receives a bounded failure without a ready artifact, and retry can verify and adopt the complete content under current claim checks

#### Scenario: A source stream is incomplete
- **WHEN** source enumeration fails, exceeds its byte cap, or misses its deadline
- **THEN** no complete staging object is installed from its partial bytes and no download is issued

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

### Requirement: Full verification requires no live cloud services
The standard test command SHALL run ordinary tests with the in-memory adapter. The full repository verification command SHALL additionally exercise the real S3 adapter against local VersityGW, including HTTPS transfers, actual upload-cap enforcement, invalid/expired authorization, byte verification, immutable publication races, protected downloads, and export delivery. These commands SHALL require no AWS credentials, cloud storage account, or cloud API access; initial toolchain and container-image downloads are separate setup dependencies. Failure to start or reach required local integration services SHALL fail the full gate explicitly, rather than silently skip those checks.

#### Scenario: Full verification on a machine without AWS credentials
- **WHEN** dependencies and the pinned local images are available and full verification runs
- **THEN** both ordinary and local storage integration checks execute without cloud API access

#### Scenario: Local integration setup fails
- **WHEN** the required local storage service cannot be started
- **THEN** the full gate reports failure rather than reporting success from the ordinary suite alone

### Requirement: Provider qualification is separate from local compatibility
The change SHALL record which behaviors were verified against the pinned local service. A separately invoked deployment check SHALL exercise a disposable isolated namespace against the configured AWS deployment, including its real permissions, TLS, upload restrictions, immutable publication, and delivery headers. This check SHALL never run implicitly from development startup, ordinary tests, or full local verification. Passing local checks SHALL NOT be reported as verification of an untested AWS deployment. Local compatibility defects SHALL be resolved or explicitly block qualification; they SHALL NOT be hidden by weakening production invariants or silently replacing approved local storage.

#### Scenario: A deployment has not been checked
- **WHEN** local verification passes but the AWS deployment check has not run
- **THEN** the result reports local compatibility success and AWS deployment verification as not performed
