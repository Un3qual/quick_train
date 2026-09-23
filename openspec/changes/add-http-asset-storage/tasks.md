## 1. Dependencies and local protocol foundation

- [ ] 1.1 Inspect applicable Ash/Igniter generators before scaffolding; use them where needed, then deliberately edit the existing embedded access resource. Add stable pinned ExAws/ExAws.S3 and required parsing dependencies using mise, keeping `mix.exs`, `mix.lock`, and any tool pins coherent without unrelated upgrades.
- [ ] 1.2 Add the official VersityGW v1.8.0 image with a verified digest to Compose, loopback-only ports, native TLS, persistent POSIX/version-history volumes, and ignored local credential/certificate material. Add `storage.setup`, `storage.start`, and `storage.stop`; make existing database stop service-scoped.
- [ ] 1.3 Implement idempotent local bucket/versioning/CORS bootstrap using explicit local credentials and trusted TLS. Document certificate trust setup, verify persistence across restart, and reject missing versioning or an insecure endpoint.
- [ ] 1.4 Establish a reusable integration runner with a unique disposable gateway container/volume and dynamic loopback port. Verify signed POST size/expiry enforcement, version-specific reads, checksums, and conditional PUT behavior on the pinned gateway before relying on them in publication; treat incompatibility as a blocker, not a skipped check.

## 2. Upload descriptors and GraphQL compatibility

- [ ] 2.1 Extend `StorageMethod`, the descriptor type/validator, and embedded `StorageAccess` with POST, sensitive string-valued form fields, and the file field name. Preserve GET/PUT representations and reject upload-only fields on read access.
- [ ] 2.2 Add focused descriptor/GraphQL tests for POST serialization, malformed form fields, destination/expiry bounds, existing PUT support, rejection before ordinary asset persistence, and preservation of existing task-owned asset identity on issuance failure.
- [ ] 2.3 Generate signed POST policies with exact staging keys, receiver-enforced registered-size caps, conservative expiry, private fixed metadata, and no redirect/prefix grants. Verify a real local upload and rejection of oversized or tampered requests.

## 3. S3 configuration and bounded transport

- [ ] 3.1 Add the S3 adapter and explicit runtime configuration for endpoints, bucket, region, credentials, addressing, TLS, and application host/cookie isolation. Preserve InMemory for ordinary tests and fail closed for absent/invalid storage configuration without AWS fallback or metadata-service discovery.
- [ ] 3.2 Integrate the existing Req transport with SDK signing/operations, disable redirects and uncontrolled retries/decoding, stream exact bytes, bound control/error bodies, and map failures without leaking signed URLs, form values, or credentials.
- [ ] 3.3 Implement one monotonic operation deadline covering enumeration, hashing, HTTP work, and retries, with caller-owned temporary-file cleanup and cancellation of local workers/streams. Correct the remote-timeout callback documentation while preserving stronger InMemory guarantees.

## 4. Verified immutable publication

- [ ] 4.1 Implement version-pinned staging HEAD/GET with bounded private spooling, incremental SHA-256/length verification, rejection of missing/null versions, and no canonical write for mismatched or incomplete bytes.
- [ ] 4.2 Implement checksum-protected single canonical PUT with `If-None-Match: *`, fixed download metadata, and safely encoded immutable declared-media-type metadata. Preserve existing key shapes and return sanitized conditional conflicts without overwriting.
- [ ] 4.3 Implement complete canonical re-verification for both new and pre-existing objects, including hash, size, declared media type, and delivery metadata. Preserve claim rechecks, ready deduplication, and network I/O outside Ash transactions.
- [ ] 4.4 Add coordinated integration cases for staging replacement during verification, identical publication races, conflicting canonical facts, mismatched staging despite an existing matching canonical key, and stale claims. Assert one canonical object and correct database outcomes.

## 5. Direct downloads and generated exports

- [ ] 5.1 Implement signed canonical GET access with bounded expiry and authenticated attachment/octet-stream/no-store response overrides. Verify actual headers and bytes, modified/expired request rejection, optional nosniff acceptance, and storage-host/cookie isolation without an application file route.
- [ ] 5.2 Implement `write_staging/4` by consuming bounded enumerables to a private spool before checksum-protected remote PUT, then reuse existing export finalization and access. Preserve deterministic snapshot bytes, ownership, and existing failure/replacement rules.
- [ ] 5.3 Add a real export publication/download case through existing GraphQL/Tasks authorization, including a result-only reader and denied out-of-scope access. Retain ordinary InMemory lifecycle tests instead of duplicating the entire authorization suite for S3.
- [ ] 5.4 Add targeted deterministic failure tests for a blocking/interrupted enumerable, cap breach, TLS failure, redirect, dropped write response, and delayed remote completion. Verify bounded errors, cleanup, no readiness from uncertain outcomes, and safe re-verification on retry.

## 6. Verification commands and deployment contract

- [ ] 6.1 Add `storage.test` as a separate tagged test invocation and include it in `mise run verify`; leave `mise run test` on InMemory. Verify that missing local services fail explicitly and that AWS credentials are neither required nor discovered.
- [ ] 6.2 Verify concurrent integration instances and failure cleanup cannot affect development data or another run; measure a representative maximum-size transfer against the configured operation deadline without silently widening limits.
- [ ] 6.3 Implement explicitly invoked `storage.check` for a separately provisioned disposable qualification bucket with deployment-equivalent policies. Exercise runtime permission restrictions, versioning, transfer/integrity, and mandatory delivery headers; keep operator cleanup separate from the application identity and never call it from local verification.

## 7. Documentation and final validation

- [ ] 7.1 Update README, storage callback documentation, and GraphQL examples for POST method dispatch, local setup/trust, persistent development data, direct downloads with optional nosniff, no-referrer/client credential handling, and explicit production bucket/policy setup. Keep inline media and automatic maintenance deferred.
- [ ] 7.2 Reconcile proposal/specs/design/tasks with the implementation and record the pinned gateway behaviors actually verified. Report AWS qualification as not performed unless separately run; use the normal OpenSpec sync/archive workflow only after implementation is complete.
- [ ] 7.3 Run focused storage/GraphQL/export checks and `mise run openspec.validate`, then finish with `mise run verify`. Fix failures, record evidence, and commit coherent milestones before publication or merge.
