## Context

See `proposal.md` for scope and the approved download decision. Assets already own registration, expected hash/size/media-type facts, organization-scoped canonical keys, bounded publication claims, and authorization. Tasks already publish deterministic exports through that boundary. `Storage.InMemory` is the only working adapter; development and production currently leave storage unconfigured.

The default asset cap is 25 MiB. Publication has a 30-second operation budget; claims last two minutes. Upload access lasts at most 15 minutes and ordinary read access at most five minutes, further bounded by the owning workflow. These limits remain configuration, not new S3-specific lifecycle rules.

## Goals / Non-Goals

**Goals:** Implement the existing storage callbacks over S3; exercise the same implementation locally; extend transient upload access to express a browser POST; preserve current Ash authorization and publication concurrency.

**Non-Goals:** No new business resource, persistent access-token table, storage framework, file-transfer controller, multipart-upload lifecycle, media decoder, or automatic production-bucket provisioning. No database migration is expected. A temporary local spool is an implementation detail of bounded transfer, not another asset-storage adapter.

## Decisions

### 1. One S3 adapter with explicit configuration

Add `QuickTrain.Assets.Storage.S3` behind the existing callbacks. Use ExAws/ExAws.S3 for maintained S3 operations, POST policy signing, and signed URLs; reuse Req for HTTP transport and streaming. The documented ExAws HTTP-client behaviour supports a small Req integration for control requests. Transfer large bodies through Req streams using SDK-signed requests rather than making the control-response interface collect whole objects. Keep this integration private to Assets; do not add another generic HTTP abstraction or a second HTTP pool library solely for S3.

Pin stable dependency versions at implementation time and update `mix.exs` and `mix.lock` together, with any required `.mise.toml` tool pins. Use Jason already present and the SDK-supported XML parser where control operations require it. No hand-written AWS signature implementation or XML parser.

Configure endpoint, region, bucket, addressing style, explicit access key/secret and optional session token, TLS trust, and explicit application hostnames/cookie-domain scopes. Local configuration always supplies local values and disables ambient credential discovery and cloud-metadata lookup. Production has no local or in-memory fallback; unconfigured storage retains the current fail-closed error, and partially configured or insecure storage is rejected. Production AWS uses a regional HTTPS endpoint; local VersityGW uses its directly configured HTTPS endpoint. Both must serve requests without redirects and preserve certificate and hostname verification.

The adapter owns protocol I/O only. Existing Ash actions remain responsible for permissions, ownership, asset registration, claims, deduplication, and readiness. Do not add database access to the adapter or move network calls into Ash transactions.

Alternative: a filesystem adapter would be simpler in isolation but would not test the production protocol. A second SDK HTTP client adds dependencies without serving this design.

### 2. Signed POST policies enforce client-upload caps

Extend `StorageMethod`, the storage descriptor type/validator, and embedded `StorageAccess` with `:post`, a sensitive string-valued `form_fields` map, and `file_field` (S3 uses `file`). Keep existing GET/PUT descriptors intact. These fields are transient protocol data, not persisted domain JSON. Use the repository's Ash generator/codegen workflow where applicable; no new resource table is needed.

Use `ExAws.S3.presigned_post` with an exact staging key, fixed non-rendering object headers, no success redirect, and `content-length-range` bounded by the registered size. Omit the SDK `:acl` option and any `acl` form field or policy condition; backend PUTs likewise omit ACL headers. Production AWS uses Bucket owner enforced Object Ownership with ACLs disabled, S3 Block Public Access enabled, and bucket/identity policies granting only the required authenticated staging/publication/read operations. Privacy comes from these controls, not an `acl: private` upload field. Local VersityGW uses the same ACL-free requests with private bucket permissions; it need not implement AWS ownership-control APIs. Qualification verifies signed uploads work and unsigned object reads/writes are denied.

Build the fixed POST fields (`Content-Type: application/octet-stream`, `Content-Disposition: attachment`, `Cache-Control: no-store`, and any additional fixed metadata) once. Use those same names/values for exact `custom_conditions` and merge them into the SDK-returned fields when producing `form_fields`, preserving SDK-generated key/signature/credential fields. `custom_conditions` alone does not populate the SDK's returned fields. Object header values belong in multipart form fields, not the outer multipart request's Content-Type header. The policy permits only the expected fields; it does not grant a key prefix or a canonical write. Do not trust client checksums as proof of finalization. The browser sends the descriptor's fields unchanged, appends the file, and lets its multipart encoder generate the boundary. Verify that this descriptor and the file alone suffice, and that removing or changing a required fixed field is rejected. This is a single POST object upload, not S3 multipart upload.

The policy range bounds file-content bytes, excluding the multipart envelope. Keep the maximum equal to the registered size without an overhead allowance; qualify the gateway with exact-cap success and cap-plus-one rejection using real multipart requests.

Compute integer-second signature lifetimes conservatively so the signed expiry and descriptor never exceed the requested expiry; reject nonpositive remaining lifetimes. Validate the complete method-specific descriptor before ordinary registration persists an asset. Invalid descriptors for already-committed task-owned assets preserve identity, original expiry, and retry semantics.

Alternative: a conventional presigned PUT does not express the POST policy's receiver-enforced size range. Finalization-only size rejection would not meet the upload-cap requirement.

### 3. Versioned staging and conditional canonical publication

Use one private, version-enabled bucket per environment with the existing `assets/staging/<organization>/<asset>` and `assets/sealed/<organization>/<sha256>` key shapes. Clients receive only operation-specific staging POST or sealed GET access. Require versioning to be enabled and verified during bootstrap/qualification; reject a missing/null staging version instead of silently proceeding without a stable source.

Publication follows the existing claim outside the database transaction:

1. HEAD staging to select a version and reject a declared remote length outside the expected size/cap. Read that exact version thereafter.
2. Stream its complete bytes to a private temporary file while counting and hashing them. Stop on excess length, mismatch, read failure, or deadline. A staging overwrite cannot change this selected version.
3. Only after full size/SHA-256 verification, stream a single PUT from the spool to the canonical key with `If-None-Match: *`. Include exact Content-Length and a provider-validated full-object checksum. Set attachment, octet-stream, and no-store metadata. Store `declared-media-type-sha256` as application metadata containing the 64 lowercase hexadecimal characters of SHA-256 over the exact persisted media-type UTF-8 bytes. Keep the original value in the database, never in response Content-Type; this bounded representation preserves currently accepted long or non-ASCII values without a new registration limit.
4. If canonical content already exists, do not overwrite it. Re-read and verify its complete hash, size, declared-media-type digest against the expected database fact, and delivery metadata. Missing, malformed, or mismatched media-type digests are conflicts. The same verification is required after our own successful PUT. ETag or uploader metadata alone is never integrity evidence; only the backend sets canonical metadata, and it still verifies complete content bytes. Conditional conflicts either lead to bounded re-verification or a retryable sanitized failure.
5. Return only the verified existing contract facts. The existing Ash commit phase rechecks claim ownership/expiry, and ready uniqueness resolves concurrent registrations. The loser can become `duplicate_content`; no per-registration canonical copy is created.

Always verify the selected staging bytes before reusing existing canonical content, so an incorrect upload cannot succeed by naming another asset's hash. Canonical keys are write-once for the application: production permissions must prevent deletion and unconstrained replacement of sealed objects, and no cleanup command can target them as staging. Versioning alone does not prevent overwrites or delete markers.

Alternative: an unguarded server-side copy risks publishing a different staging version and overwriting the destination. Bounded spooling plus a conditional PUT makes the transferred bytes and destination precondition explicit, at the cost of extra I/O.

### 4. Direct signed downloads with optional nosniff

The existing authorized access actions return SDK-signed GET descriptors for the canonical key. Set attachment, octet-stream, and no-store on canonical objects and sign the corresponding GET response overrides. Changing the key, expiry, or signed overrides invalidates authorization. Keep the existing five-minute/workflow expiry bounds and explicit semantics that revocation stops new issuance, not already-issued capabilities. Expiry is checked when a transfer starts; it does not promise to interrupt an already accepted download.

Configure a storage hostname distinct from all application hostnames and outside application-cookie scope; another port on the application hostname is insufficient. Require machine-readable lists of application hostnames and session-cookie Domain scopes, including consuming frontends. An explicitly empty domain list declares that all application cookies are host-only; an omitted declaration cannot qualify. Normalize DNS names and cookie domains (including a leading dot), reject an application-host match, and reject a storage hostname equal to or ending in a dot plus any declared cookie domain. Thus `storage.example.com` with a `.example.com` application cookie is rejected even if the application uses `app.example.com`. Validate this configuration before issuing storage access; operators must keep the declarations accurate because the backend cannot inspect frontend runtime cookies. No cookie-discovery service is needed.

Clients send no QuickTrain cookies or bearer token to storage, use no-referrer access handling, and never embed these URLs as scripts, styles, or inline content. If browser fetch uploads/downloads are used, configure CORS for explicit application origins and the required transfer methods/headers; do not treat CORS as authorization. Plain download navigation does not require a broad CORS policy.

Nosniff remains welcome when the storage endpoint supplies it, but its absence does not disqualify this isolated download-only path. Attachment and isolation are not claimed to replicate its script/style protections. Do not add a CDN, proxy, Phoenix route, header-injection capability, or fake descriptor request header to manufacture it. GraphQL remains the only application API. A future inline-media change must define its own rendering contract.

Alternative: maintaining mandatory nosniff would require a response-header layer or moving bytes through QuickTrain. The user approved the narrower direct-download contract instead.

### 5. Bounded streaming exports and honest timeout outcomes

Implement `write_staging/4` for the existing enumerable caller. Consume into a private spool under the byte cap and one monotonic operation deadline, computing length/checksum before issuing a single complete PUT. This deliberately adds a bounded disk pass for exports that already originate from a file; it preserves the public enumerable contract without a new file-path API. An enumeration exception or cap breach never starts a remote upload. Use exact Content-Length and checksum validation so an interrupted transfer cannot install its received prefix as a complete object.

Bound enumeration, hashing, connection, response, retry, and cleanup work by the operation budget; per-request timeouts alone cannot bound a blocking enumerable. Ensure the caller owns temporary-file cleanup even if its worker is terminated. Disable automatic redirects, body decoding/decompression, and uncontrolled client retries; preserve the exact stored bytes. Bound error/control bodies, map failures to the existing closed error contract, and keep signed URLs, form fields, and credentials out of logs.

Correct the storage callback documentation's promise that timeout proves the provider can never commit later, and apply the matching `task-results` delta to its export deadline scenario. A complete write may succeed after its response is lost. Fail without readiness, then let a later attempt reverify content under a current claim. Do not delete canonical bytes to compensate for uncertainty. Retain the in-memory adapter's stronger local cancellation guarantees and its adapter-specific tests without attributing them to remote S3 in shared contracts or tests.

Task exports retain their current sealed snapshot, deterministic JSONL, ownership, replacement rules, and finalization path. This change does not create an export retry subsystem or change result authorization.

### 6. Local VersityGW with disposable integration instances

Pin the official VersityGW Docker image for stable release v1.8.0; verify the published image reference and record its digest during implementation. Use its POSIX backend in a Linux Docker volume, with its version-history directory separate from the bucket directory. Enable bucket versioning explicitly. Persist both current objects and version history for development. Bind published ports to loopback.

Use gateway-native TLS with an explicitly trusted development certificate; do not introduce a header proxy. Provide a mise setup command that creates ignored local certificate material and documents browser trust installation. Tests pass the CA explicitly and validate hostname/chain. Use distinct loopback host identities for QuickTrain and storage; make the development endpoint and certificate SANs agree. Machine-wide trust-store changes remain an explicit developer setup step.

Extend the existing Compose/mise workflow with `storage.setup`, `storage.start`, `storage.stop`, and `storage.test`. Make stop operations service-scoped so stopping PostgreSQL does not unexpectedly tear down storage. Setup is idempotent: create/verify the development bucket, versioning, and scoped browser CORS using local credentials, without wiping files. Keep credentials and certificate keys out of Git.

For each integration run, start a dedicated gateway container with a unique name/volume and an allocated loopback port, using the same pinned image and bootstrap logic. Remove only that run's container and volume on success or failure. No global Compose down/reset, shared bucket purge, or new fixed subnet is needed. This isolates parallel runs and removes object versions without adding a general storage-cleanup service. Ordinary development restart preserves data.

Alternative: sharing the development bucket would require careful version-aware prefix cleanup and would risk user data; a disposable local instance is a smaller isolation boundary.

### 7. Separate fast tests, local protocol checks, and deployment qualification

Keep `mise run test` on `Storage.InMemory`. Run tagged S3 tests in a separate BEAM invocation selected by `storage.test`, so adapter configuration cannot leak into the ordinary suite. The integration runner supplies only its local endpoint, credentials, CA, and bucket. Absence of the gateway fails the integration command instead of skipping it. Add `storage.test` to `mise run verify` after the existing checks. This removes live cloud-storage dependencies; existing dependency-audit traffic and initial package/image downloads still have their normal network requirements.

Cover actual POST cap/expiry/signature enforcement, GET expiry and tampering, mandatory download response headers with optional nosniff, complete-byte verification, version pinning under an overwrite, canonical conditional-write races/conflicts, and end-to-end export publication/access. Use coordinated barriers for races. Use the existing local HTTP-test patterns to exercise dropped responses, invalid TLS/redirects, and slow/interrupted streams where a real gateway cannot deterministically trigger them. These targeted failures complement rather than replace the real gateway tests.

Provide an explicitly invoked `storage.check` deployment command that uses the deployment's configured endpoint, region, bucket, and application identity. Inspect versioning, Bucket owner enforced ownership, Block Public Access, permission restrictions, and the complete staging lifecycle configuration on that exact bucket; a disposable bucket with copied policies cannot qualify the runtime bucket. Exercise integrity/publication, TLS, ACL-free uploads using only the descriptor and file, denied unsigned reads/writes, and delivery responses using a fresh run UUID in the organization segment of the normal `assets/staging/<run-uuid>/...` and `assets/sealed/<run-uuid>/...` key shapes. This isolates probe objects while exercising the production prefix policies; do not add qualification-only policy exceptions or substitute a privileged identity for application operations.

Test denied sealed-object deletion/replacement only against objects created by this run with the application identity; do not grant deletion solely to simplify cleanup. Use an operator identity to inspect that same bucket's configuration; missing inspection access fails qualification. Track the run's exact probe keys and version IDs for operator cleanup, or report them when cleanup credentials are absent. Never mutate pre-existing objects or bucket configuration. Report the checked endpoint and bucket, and require a new check when the target, application identity, or relevant bucket controls change; results do not transfer between buckets. The command is never a dependency of setup, test, or local verify. Report local compatibility and deployment qualification separately; no AWS check is claimed until it actually runs.

Production qualification requires native lifecycle expiration scoped only to `assets/staging/`: expire current versions, permanently expire noncurrent versions without a retained-version-count exception, and remove expired delete markers. Use simple enabled prefix rules, with delete-marker cleanup in a separate rule where required by S3. Both current and noncurrent expiration ages must be finite and strictly exceed a conservative safety window: maximum staging lifetime plus upload-access lifetime, publication-claim lifetime, and operation budget. One day satisfies the current defaults; reject that setting if configured lifetimes make it unsafe. Read the complete lifecycle configuration and reject broader or overlapping expiration/transition rules that could shorten this window or affect `assets/sealed/`. Qualification also requires staging expiration not to be blocked by retention/Object Lock or replication configuration. Accept only this documented simple configuration; do not build a general lifecycle-policy interpreter or automatically modify the bucket.

Test acceptance/rejection with deterministic configuration fixtures rather than waiting for lifecycle execution. Lifecycle deletion is asynchronous, so this prevents indefinite configured retention, not replay-driven growth within the window, a hard byte quota, or an exact cleanup deadline. Local development retains its explicit reset and tests use disposable volumes; they need no lifecycle scheduler. Application-managed maintenance for credentials/imports and broader operator readiness remain deferred, so this prerequisite alone does not claim an unattended-ready backend.

## Risks / Trade-offs

- **Local S3 behavior may differ from AWS** → qualify v1.8.0 with real tests early and retain a separate deployment check. A protocol gap blocks implementation qualification; it does not silently select another gateway or weaken an invariant.
- **Optional nosniff removes a browser defense** → preserve mandatory download headers and isolated hosts, exclude executable/inline use, and retain nosniff when provided. Do not advertise equivalence to the former header contract.
- **Extra disk/network I/O can exhaust the 30-second budget** → stream bounded files, use one deadline, clean up deterministically, and measure representative maximum-size transfers. Do not silently extend claims or limits.
- **Replay and version history consume storage** → require native production staging/version expiration beyond the active-use safety window, use disposable test volumes, and document explicit development reset. Retention is asynchronous and does not impose a hard storage quota; application-managed maintenance remains deferred.
- **A remote commit can outlive its caller's timeout** → keep objects private, preserve claim fencing, and reverify on retry; never claim database/remote-storage atomicity.
- **An existing canonical object may have conflicting facts or unsafe delivery metadata** → fail qualification/publication rather than overwrite immutable bytes or trust caller metadata.
- **Client compatibility changes for uploads** → expose POST fields explicitly in GraphQL and document method dispatch; keep legacy PUT test adapters supported.

## Migration Plan

1. Add local gateway/TLS bootstrap and validate its required protocol behavior before completing the adapter. Pin dependencies without unrelated upgrades.
2. Add POST descriptors and S3 callbacks while leaving ordinary tests on InMemory. No data migration is expected; production currently has no working HTTP adapter to convert.
3. Reconcile `Storage` documentation, GraphQL examples, README, and verification commands with this approved contract. Run focused tests and the complete local gate.
4. For deployment, have the operator provision a private versioned bucket, safe staging/version lifecycle rules, isolated endpoint, explicit application host/cookie-domain declarations, least-privilege credentials, and explicit CORS if needed. Run `storage.check` with the intended runtime configuration against that exact bucket before enabling storage access; only that checked target and application identity qualify. Never change bucket contents during ordinary application startup.
5. Roll back by disabling new storage access or restoring the previous application release/configuration while retaining private objects and database facts. Do not substitute InMemory in production or delete storage to roll back. Already-issued signed capabilities retain their original expiry.

## Implementation and verification evidence

Implemented on 2026-09-23 with exact ExAws 2.7.0, ExAws.S3 2.5.9, and SweetXml 0.7.5
dependencies, reusing Req 0.7.2. Existing Ash/Igniter generators were inspected; the access
descriptor is an existing embedded resource, so it was edited directly without persistence
generation or a migration. The runtime uses explicit SDK configuration maps and direct SDK
operations so ambient ExAws configuration cannot select credentials or metadata discovery.

The verified gateway is `versity/versitygw:v1.8.0@sha256:30292fc2eeacc67a36993b01f7a7a5e3361a19cced0e80c1d71cfa2a4b0a2499`.
Local HTTPS checks demonstrated exact-cap multipart uploads, cap-plus-one rejection, fixed-field
and signed-policy tampering rejection, expired POST/GET rejection, version-specific reads,
checksum rejection, conditional PUT conflict behavior, denied unsigned access, and authenticated
download response headers. Coordinated lifecycle and export tests exercise current claims,
publication races, staging replacement, long/non-ASCII media types, stale claims, lost responses,
delayed remote completion, and deterministic snapshot retries. Temporary verification HTTP
failures preserve pending identity rather than being reported as permanent content conflicts.

An isolated development setup/restart check preserved credentials, certificates, current bytes,
and prior versions. CORS accepted the configured localhost origin and rejected another origin;
plaintext requests failed. Concurrent disposable runs (one successful, one intentionally failed)
removed only their own containers and volumes. A missing Docker endpoint caused an explicit
integration failure. In the final gate, a measured 25 MiB staging write took 167 ms and publication took 468 ms,
against the existing 30,000 ms budget per operation on this machine; these are observations,
not a production latency guarantee.

The deployment command is separate from local verification. Deterministic fixtures check exact
runtime target binding, safe lifecycle/ownership/public-access controls, and cleanup isolation.
AWS deployment qualification has **not been performed**. The live application-identity probes
must run against the intended AWS configuration before that deployment is considered qualified.
The independent review's three findings were fixed and verified: transient verification HTTP
failures preserve retryability, protocol fixtures cannot merge ambient SDK credentials, and
malformed inspection/inventory XML returns sanitized failures while preserving cleanup manifests.

Final local validation passed:

- `mise run openspec.validate`: all 15 changes/specifications valid.
- `QUICK_TRAIN_TEST_DATABASE_NAME=quick_train_ae1a_root_test mise run verify`: formatting,
  Ash code-generation check, compile boundaries/cycles, strict Credo/Reach, zero clone budget,
  Dialyzer (zero errors), dependency audit (no retired/advisory packages), production compilation,
  409 ordinary tests, and 22 disposable HTTPS storage tests all passed. The dedicated ordinary
  test database avoids modifying unrelated development/test schemas; the integration runner
  separately creates and removes its own UUID database.
- The final integration run used ExUnit seed `714320`; its 22 tests completed in 8.5 seconds.

### Approved code-quality review follow-up

The four approved review improvements are implemented. Development setup and integration fixtures
now call `S3.LocalSetup` with the existing validated S3 configuration, sharing bucket creation,
versioning, and scoped CORS setup. Result-export transitions use narrow named Ash update actions
and Tasks interfaces. Asset finalization uses Assets interfaces for its existing update actions
and scoped locked/canonical reads. Qualification uses ExAws inspection constructors where
available, and its fixtures independently specify the expected protocol requests.

The new allowed-origin CORS regression first failed with HTTP 403 against the old fixture; it
passes through the shared bootstrap. Gateway tests also reject unapproved origins and non-local
bootstrap targets and confirm that repeated bootstrap preserves stored bytes and version history.
The shared setup removes 34 lines of duplicated setup/configuration code. An independent review
found no actionable issues; existing public contracts, claim fencing, and transaction boundaries
remain unchanged.

Follow-up validation on 2026-09-23 passed 85 focused qualification/lifecycle/export/concurrency/
GraphQL tests, then the complete
`QUICK_TRAIN_TEST_DATABASE_NAME=quick_train_ae1a_root_test mise run verify` gate: all static/build
checks, 409 ordinary tests, and 24 disposable HTTPS storage tests. The final integration seed was
`913268`; its 25 MiB transfer measured 177 ms for staging and 494 ms for publication against the
existing 30,000 ms per-operation budget. AWS qualification remains not performed.

All implementation and approved review tasks are complete. This active change is ready for the
normal OpenSpec sync/archive workflow; its delta specifications have not been archived into the
main specs yet.

### Branch-scoped simplification review

This review covers the HTTP storage feature range `5d77899..aa23adc`. The later
repository-wide cleanup is outside this review's scope. The three reviewed S3 modules
are 21 production lines shorter after these changes:

- Qualification uses SweetXml's XPath sigils and native record mapping rather than
  constructing XPath structs and mapping inventory nodes manually. Explicit bounded
  parsing with `dtd: :none` remains necessary; the SDK's default inventory parser does
  not provide that parsing boundary. Lifecycle validation still rejects unknown controls.
- Transfer and qualification probes retain native Req responses and use its header API.
  Only the ExAws callback converts them to the SDK response shape. Qualification POSTs
  use `form_multipart` through the normal request pipeline instead of invoking an
  encoding step and manually forwarding its encoded body and headers.
- Signed download overrides derive from the existing delivery headers, keeping upload,
  publication, and download metadata consistent without a second list.

The architecture review retained the explicit credential configuration, version pinning,
incremental size/hash verification, caller-owned spool cleanup, bounded control bodies,
and separate operator identity. These enforce concrete storage contracts. Ash already
owns the narrow asset/export transitions, locked claims, and readiness decisions; no
additional persistence wrapper or resource is needed. The disposable runner's per-resource
cleanup tracks partial startup so failures cannot affect development data or another run.

Focused verification passed 32 tests (seed `728070`) and all 24 disposable HTTPS tests
(seed `793018`). The existing upload test now exercises the same native multipart
transport used by qualification; the cleanup fixture includes object versions and delete
markers without assuming their order. Full verification is pending. AWS deployment
qualification remains not performed.

## References

- [ExAws.S3 policy signing, operations, and signed URLs](https://ex-aws-s3.hexdocs.pm/ExAws.S3.html)
- [ExAws HTTP client behaviour and Req integration](https://ex-aws.hexdocs.pm/ExAws.Request.HttpClient.html)
- [VersityGW v1.8.0](https://github.com/versity/versitygw/releases/tag/v1.8.0) and [POSIX backend](https://github.com/versity/versitygw/wiki/POSIX-Backend)
- [S3 POST policy conditions](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-HTTPPOSTConstructPolicy.html), [conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html), and [GetObject response overrides](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html)
- [S3 user-metadata limits](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingMetadata.html) and [versioned lifecycle expiration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html)
- [S3 Object Ownership with ACLs disabled](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) and [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)

These references inform the design; they are not evidence that QuickTrain's integration or an AWS deployment has been tested.
