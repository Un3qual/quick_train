## 1. Dependencies and local protocol foundation

- [x] 1.1 Inspect applicable Ash/Igniter generators before scaffolding; use them where needed, then deliberately edit the existing embedded access resource. Add stable pinned ExAws/ExAws.S3 and required parsing dependencies using mise, keeping `mix.exs`, `mix.lock`, and any tool pins coherent without unrelated upgrades.
- [x] 1.2 Add the official VersityGW v1.8.0 image with a verified digest to Compose, loopback-only ports, native TLS, persistent POSIX/version-history volumes, and ignored local credential/certificate material. Add `storage.setup`, `storage.start`, and `storage.stop`; make existing database stop service-scoped.
- [x] 1.3 Implement idempotent local bucket/versioning/CORS bootstrap using explicit local credentials and trusted TLS. Document certificate trust setup, verify persistence across restart, and reject missing versioning or an insecure endpoint. Accept the configured local HTTPS endpoint without requiring an AWS regional hostname.
- [x] 1.4 Establish a reusable integration runner with a unique disposable gateway container/volume and dynamic loopback port. Verify signed POST exact-cap success, cap-plus-one rejection, expiry enforcement, version-specific reads, checksums, and conditional PUT behavior on the pinned gateway before relying on them in publication; treat incompatibility as a blocker, not a skipped check.

## 2. Upload descriptors and GraphQL compatibility

- [x] 2.1 Extend `StorageMethod`, the descriptor type/validator, and embedded `StorageAccess` with POST, sensitive string-valued form fields, and the file field name. Preserve GET/PUT representations and reject upload-only fields on read access.
- [x] 2.2 Add focused descriptor/GraphQL tests for POST serialization, malformed form fields, destination/expiry bounds, existing PUT support, rejection before ordinary asset persistence, and preservation of existing task-owned asset identity on issuance failure.
- [x] 2.3 Generate signed POST policies with exact staging keys, receiver-enforced registered-file-size caps without a multipart-overhead allowance, conservative expiry, fixed object metadata, and no ACL fields/conditions or redirect/prefix grants. Derive exact policy conditions and matching `form_fields` from the same fixed values, preserving SDK-generated authorization fields. Verify a real local upload using only the descriptor and file; reject missing/changed fixed fields, oversized or tampered requests, and unsigned reads/writes. Keep object Content-Type separate from the encoder's multipart request Content-Type.

## 3. S3 configuration and bounded transport

- [x] 3.1 Add the S3 adapter and explicit runtime configuration for endpoints, bucket, region, credentials, addressing, TLS, and application host/cookie-domain lists, including an explicit empty list for host-only cookies. Apply the regional endpoint rule only to AWS, validate the local HTTPS identity, and reject redirects in both profiles. Preserve InMemory for ordinary tests and fail closed for absent/invalid storage configuration without AWS fallback or metadata-service discovery.
- [x] 3.2 Integrate the existing Req transport with SDK signing/operations, disable redirects and uncontrolled retries/decoding, stream exact bytes, bound control/error bodies, and map failures without leaking signed URLs, form values, or credentials.
- [x] 3.3 Implement one monotonic operation deadline covering enumeration, hashing, HTTP work, and retries, with caller-owned temporary-file cleanup and cancellation of local workers/streams. Reconcile the remote-timeout callback documentation and provider-neutral export assertions with the `task-results` delta while preserving stronger InMemory guarantees and adapter-specific tests.

## 4. Verified immutable publication

- [x] 4.1 Implement version-pinned staging HEAD/GET with bounded private spooling, incremental SHA-256/length verification, rejection of missing/null versions, and no canonical write for mismatched or incomplete bytes.
- [x] 4.2 Implement checksum-protected single canonical PUT with `If-None-Match: *`, fixed download metadata, and a fixed 64-character lowercase SHA-256 digest of the exact persisted media-type bytes as `declared-media-type-sha256` metadata. Preserve accepted media-type values and existing key shapes; return sanitized conditional conflicts without overwriting.
- [x] 4.3 Implement complete canonical re-verification for both new and pre-existing objects, including hash, size, expected declared-media-type digest, and delivery metadata; reject missing, malformed, or mismatched digests. Preserve claim rechecks, ready deduplication, and network I/O outside Ash transactions.
- [x] 4.4 Add coordinated integration cases for staging replacement during verification, identical publication races, conflicting canonical facts (including media-type digests), mismatched staging despite an existing matching canonical key, and stale claims. Include successful publication/reuse of long and non-ASCII media-type values; assert one canonical object and correct database outcomes.

## 5. Direct downloads and generated exports

- [x] 5.1 Implement signed canonical GET access with bounded expiry and authenticated attachment/octet-stream/no-store response overrides. Verify actual headers and bytes, modified/expired request rejection, optional nosniff acceptance, and storage-host/cookie isolation without an application file route. Cover same-host and parent-cookie-domain rejection, omitted cookie declarations, and valid distinct hosts with explicit host-only cookie scopes.
- [x] 5.2 Implement `write_staging/4` by consuming bounded enumerables to a private spool before checksum-protected remote PUT, then reuse existing export finalization and access. Preserve deterministic snapshot bytes, ownership, and existing failure/replacement rules.
- [x] 5.3 Add a real export publication/download case through existing GraphQL/Tasks authorization, including a result-only reader and denied out-of-scope access. Retain ordinary InMemory lifecycle tests instead of duplicating the entire authorization suite for S3.
- [x] 5.4 Add targeted deterministic failure tests for a blocking/interrupted enumerable, cap breach, TLS failure, redirect, dropped write response, and delayed remote completion. Verify bounded errors, cleanup, no incomplete installed content or readiness from uncertain outcomes, and complete-byte/current-claim re-verification on retry. Assert retained sealed snapshots and pending-asset identity under existing expiry/replacement rules even when complete private remote bytes appear after timeout.

## 6. Verification commands and deployment contract

- [x] 6.1 Add `storage.test` as a separate tagged test invocation and include it in `mise run verify`; leave `mise run test` on InMemory. Verify that missing local services fail explicitly and that AWS credentials are neither required nor discovered.
- [x] 6.2 Verify concurrent integration instances and failure cleanup cannot affect development data or another run; measure a representative maximum-size transfer against the configured operation deadline without silently widening limits.
- [x] 6.3 Implement explicitly invoked `storage.check` against the exact configured runtime endpoint, region, bucket, and application identity. Use a fresh run UUID within normal staging/sealed key shapes under production policies; restrict mutation probes and cleanup to that run's keys/versions. Exercise runtime permission restrictions, versioning, transfer/integrity, and mandatory delivery headers. Require Bucket owner enforced ownership and Block Public Access; verify ACL-free POST success using only the descriptor and file, ACL-free backend PUTs, and denial of unsigned reads/writes. Inspect that bucket's complete native staging lifecycle configuration; require safe current/noncurrent expiration and delete-marker cleanup, and reject missing/disabled rules, retention blockers, unsafe ages, version-count exceptions, or expiration/transition rules affecting sealed objects. Use deterministic configuration fixtures instead of waiting for expiration; cover a passing disposable bucket with an invalid runtime bucket and isolation from pre-existing objects. Report the checked target and require requalification when it, the application identity, or relevant bucket controls change. Keep operator inspection/cleanup separate from the application identity and never call the deployment check from local verification.

## 7. Documentation and final validation

- [x] 7.1 Update README, storage callback documentation, and GraphQL examples for POST method dispatch, local setup/trust, persistent development data, direct downloads with optional nosniff, no-referrer/client credential handling, explicit application host/cookie-domain declarations, and production bucket/policy setup. Reconcile the Assets staging-expiry contract with provider-native retention while preserving expiry and finalizer-claim guarantees. Document native staging lifecycle qualification and its asynchronous retention limits separately from deferred application-managed maintenance and broader operator readiness. Keep inline media deferred.
- [x] 7.2 Reconcile proposal/specs/design/tasks with the implementation and record the pinned gateway behaviors actually verified. Report AWS qualification as not performed unless separately run; use the normal OpenSpec sync/archive workflow only after implementation is complete.
- [x] 7.3 Run focused storage/GraphQL/export checks and `mise run openspec.validate`, then finish with `mise run verify`. Fix failures, record evidence, and commit coherent milestones before publication or merge.

## 8. Approved code-quality review follow-up

- [x] 8.1 Share validated S3 configuration and one local bucket/versioning/CORS bootstrap between development setup and integration fixtures; exercise actual CORS acceptance/rejection and idempotence in the disposable gateway suite.
- [x] 8.2 Replace the result-export catchall internal update with narrow named lifecycle actions and Tasks code interfaces, preserving locked records, transactions, retry behavior, and internal authorization.
- [x] 8.3 Expose existing asset finalization update actions through Assets code interfaces and use the existing scoped asset read interface for locked/canonical lookups without changing publication or missing-record behavior.
- [x] 8.4 Use native ExAws bucket inspection operations where available; make qualification request fixtures independent of the implementation and remove the test-only inspection-resource helper.
- [x] 8.5 Review the combined changes, run focused checks and the full `mise run verify` gate, update implementation evidence, and commit the approved cleanup.

## 9. Branch-scoped simplification review

- [x] 9.1 Review the HTTP storage implementation range `5d77899..aa23adc`, including its configuration, transport, qualification, scripts, tests, and Ash lifecycle integration; exclude the later repository-wide cleanup from this review's scope.
- [x] 9.2 Replace custom XPath construction and inventory mapping with SweetXml sigils and mapping; preserve bounded parsing, DTD rejection, complete inventory checks, and exact cleanup scope.
- [x] 9.3 Keep native Req responses through transfer/probe code, adapt responses only at the ExAws callback, and use Req's header and multipart APIs. Derive signed download overrides from the existing delivery headers.
- [x] 9.4 Verify focused fixtures and disposable HTTPS integration, including multipart encoding and cleanup of both object versions and delete markers; commit the simplifications.
- [x] 9.5 Run independent OpenSpec validation and the complete verification gate, record results, and commit closeout.

## 10. Second branch-scoped simplification pass

- [x] 10.1 Replace lifecycle summary accumulation with native collection operations while retaining complete-rule validation; check multiple valid rules and mixed valid/invalid rules.
- [x] 10.2 Simplify the private signed-request interface to named options without changing signing, streaming, deadlines, or error categories.
- [x] 10.3 Review the resulting diff, run focused tests, independent OpenSpec validation, and the full verification gate; record evidence and commit.

## 11. PR #11 review follow-through

- [x] 11.1 Reproduce and fix AWS dotted virtual-host bucket acceptance, root-path local bootstrap rejection, and the fault fixture's undersized body limit.
- [x] 11.2 Retry conditional PUT conflicts once with Req under the existing deadline; verify successful convergence and bounded persistent failure.
- [x] 11.3 Clarify browser CORS as a separate deployment prerequisite; retain the approved optional-cleanup manifest, exact upload cap, and disposable test isolation.
- [x] 11.4 Validate fixes and record evidence and captured-thread dispositions for publication. Reply to the captured threads during publication, then stop without fetching more reviews.
