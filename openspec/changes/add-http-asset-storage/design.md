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

Configure endpoint, region, bucket, addressing style, explicit access key/secret and optional session token, TLS trust, and application hostnames/cookie scopes. Local configuration always supplies local values and disables ambient credential discovery and cloud-metadata lookup. Production has no local or in-memory fallback; unconfigured storage retains the current fail-closed error, and partially configured or insecure storage is rejected. Require a regional HTTPS endpoint that serves requests without redirects. Preserve certificate and hostname verification in every profile.

The adapter owns protocol I/O only. Existing Ash actions remain responsible for permissions, ownership, asset registration, claims, deduplication, and readiness. Do not add database access to the adapter or move network calls into Ash transactions.

Alternative: a filesystem adapter would be simpler in isolation but would not test the production protocol. A second SDK HTTP client adds dependencies without serving this design.

### 2. Signed POST policies enforce client-upload caps

Extend `StorageMethod`, the storage descriptor type/validator, and embedded `StorageAccess` with `:post`, a sensitive string-valued `form_fields` map, and `file_field` (S3 uses `file`). Keep existing GET/PUT descriptors intact. These fields are transient protocol data, not persisted domain JSON. Use the repository's Ash generator/codegen workflow where applicable; no new resource table is needed.

Use `ExAws.S3.presigned_post` with an exact staging key, private access, fixed non-rendering object headers, no success redirect, and `content-length-range` bounded by the registered size. The policy permits only the expected fields; it does not grant a key prefix or a canonical write. Do not trust client checksums as proof of finalization. The browser sends the fields unchanged, appends the file, and lets its multipart encoder generate the boundary. This is a single POST object upload, not S3 multipart upload.

Compute integer-second signature lifetimes conservatively so the signed expiry and descriptor never exceed the requested expiry; reject nonpositive remaining lifetimes. Validate the complete method-specific descriptor before ordinary registration persists an asset. Invalid descriptors for already-committed task-owned assets preserve identity, original expiry, and retry semantics.

Alternative: a conventional presigned PUT does not express the POST policy's receiver-enforced size range. Finalization-only size rejection would not meet the upload-cap requirement.

### 3. Versioned staging and conditional canonical publication

Use one private, version-enabled bucket per environment with the existing `assets/staging/<organization>/<asset>` and `assets/sealed/<organization>/<sha256>` key shapes. Clients receive only operation-specific staging POST or sealed GET access. Require versioning to be enabled and verified during bootstrap/qualification; reject a missing/null staging version instead of silently proceeding without a stable source.

Publication follows the existing claim outside the database transaction:

1. HEAD staging to select a version and reject a declared remote length outside the expected size/cap. Read that exact version thereafter.
2. Stream its complete bytes to a private temporary file while counting and hashing them. Stop on excess length, mismatch, read failure, or deadline. A staging overwrite cannot change this selected version.
3. Only after full size/SHA-256 verification, stream a single PUT from the spool to the canonical key with `If-None-Match: *`. Include exact Content-Length and a provider-validated full-object checksum. Set attachment, octet-stream, and no-store metadata; store the immutable declared media type as safely encoded application metadata, never as the response Content-Type.
4. If canonical content already exists, do not overwrite it. Re-read and verify its complete hash, size, immutable declared media type, and delivery metadata. The same verification is required after our own successful PUT. ETag or uploader metadata alone is never integrity evidence. Conditional conflicts either lead to bounded re-verification or a retryable sanitized failure.
5. Return only the verified existing contract facts. The existing Ash commit phase rechecks claim ownership/expiry, and ready uniqueness resolves concurrent registrations. The loser can become `duplicate_content`; no per-registration canonical copy is created.

Always verify the selected staging bytes before reusing existing canonical content, so an incorrect upload cannot succeed by naming another asset's hash. Canonical keys are write-once for the application: production permissions must prevent deletion and unconstrained replacement of sealed objects, and no cleanup command can target them as staging. Versioning alone does not prevent overwrites or delete markers.

Alternative: an unguarded server-side copy risks publishing a different staging version and overwriting the destination. Bounded spooling plus a conditional PUT makes the transferred bytes and destination precondition explicit, at the cost of extra I/O.

### 4. Direct signed downloads with optional nosniff

The existing authorized access actions return SDK-signed GET descriptors for the canonical key. Set attachment, octet-stream, and no-store on canonical objects and sign the corresponding GET response overrides. Changing the key, expiry, or signed overrides invalidates authorization. Keep the existing five-minute/workflow expiry bounds and explicit semantics that revocation stops new issuance, not already-issued capabilities. Expiry is checked when a transfer starts; it does not promise to interrupt an already accepted download.

Configure a storage hostname distinct from all application hostnames and outside application-cookie scope; another port on the application hostname is insufficient. Validate the known deployment configuration and document the requirement for consuming frontends, whose runtime cookie configuration this backend cannot inspect. Clients send no QuickTrain cookies or bearer token to storage, use no-referrer access handling, and never embed these URLs as scripts, styles, or inline content. If browser fetch uploads/downloads are used, configure CORS for explicit application origins and the required transfer methods/headers; do not treat CORS as authorization. Plain download navigation does not require a broad CORS policy.

Nosniff remains welcome when the storage endpoint supplies it, but its absence does not disqualify this isolated download-only path. Attachment and isolation are not claimed to replicate its script/style protections. Do not add a CDN, proxy, Phoenix route, header-injection capability, or fake descriptor request header to manufacture it. GraphQL remains the only application API. A future inline-media change must define its own rendering contract.

Alternative: maintaining mandatory nosniff would require a response-header layer or moving bytes through QuickTrain. The user approved the narrower direct-download contract instead.

### 5. Bounded streaming exports and honest timeout outcomes

Implement `write_staging/4` for the existing enumerable caller. Consume into a private spool under the byte cap and one monotonic operation deadline, computing length/checksum before issuing a single complete PUT. This deliberately adds a bounded disk pass for exports that already originate from a file; it preserves the public enumerable contract without a new file-path API. An enumeration exception or cap breach never starts a remote upload. Use exact Content-Length and checksum validation so an interrupted transfer cannot install its received prefix as a complete object.

Bound enumeration, hashing, connection, response, retry, and cleanup work by the operation budget; per-request timeouts alone cannot bound a blocking enumerable. Ensure the caller owns temporary-file cleanup even if its worker is terminated. Disable automatic redirects, body decoding/decompression, and uncontrolled client retries; preserve the exact stored bytes. Bound error/control bodies, map failures to the existing closed error contract, and keep signed URLs, form fields, and credentials out of logs.

Correct the storage callback documentation's promise that timeout proves the provider can never commit later. A complete write may succeed after its response is lost. Fail without readiness, then let a later attempt reverify content under a current claim. Do not delete canonical bytes to compensate for uncertainty. Retain the in-memory adapter's stronger local cancellation guarantees without attributing them to remote S3.

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

Provide an explicitly invoked `storage.check` deployment command that requires a dedicated disposable qualification bucket configured with the deployment's policies and externally supplied application credentials. It checks versioning, permission restrictions, integrity/publication, TLS, and delivery response behavior without provisioning cloud infrastructure. Test denied sealed-object deletion/replacement with the application identity; do not grant deletion solely to simplify cleanup. An operator cleanup identity can remove only that run's objects and versions, otherwise report those resources for operator cleanup. The command is never a dependency of setup, test, or local verify. Report local compatibility and deployment qualification separately; no AWS check is claimed until it actually runs.

## Risks / Trade-offs

- **Local S3 behavior may differ from AWS** → qualify v1.8.0 with real tests early and retain a separate deployment check. A protocol gap blocks implementation qualification; it does not silently select another gateway or weaken an invariant.
- **Optional nosniff removes a browser defense** → preserve mandatory download headers and isolated hosts, exclude executable/inline use, and retain nosniff when provided. Do not advertise equivalence to the former header contract.
- **Extra disk/network I/O can exhaust the 30-second budget** → stream bounded files, use one deadline, clean up deterministically, and measure representative maximum-size transfers. Do not silently extend claims or limits.
- **Version history consumes disk** → use disposable test volumes and document explicit development reset. Automatic staging/version retention remains deferred operator work.
- **A remote commit can outlive its caller's timeout** → keep objects private, preserve claim fencing, and reverify on retry; never claim database/remote-storage atomicity.
- **An existing canonical object may have conflicting facts or unsafe delivery metadata** → fail qualification/publication rather than overwrite immutable bytes or trust caller metadata.
- **Client compatibility changes for uploads** → expose POST fields explicitly in GraphQL and document method dispatch; keep legacy PUT test adapters supported.

## Migration Plan

1. Add local gateway/TLS bootstrap and validate its required protocol behavior before completing the adapter. Pin dependencies without unrelated upgrades.
2. Add POST descriptors and S3 callbacks while leaving ordinary tests on InMemory. No data migration is expected; production currently has no working HTTP adapter to convert.
3. Reconcile `Storage` documentation, GraphQL examples, README, and verification commands with this approved contract. Run focused tests and the complete local gate.
4. For deployment, have the operator provision a private versioned bucket, isolated endpoint, least-privilege credentials, and explicit CORS if needed; run the separate qualification check and configure the adapter only after success. Never change bucket contents during ordinary application startup.
5. Roll back by disabling new storage access or restoring the previous application release/configuration while retaining private objects and database facts. Do not substitute InMemory in production or delete storage to roll back. Already-issued signed capabilities retain their original expiry.

## References

- [ExAws.S3 policy signing, operations, and signed URLs](https://ex-aws-s3.hexdocs.pm/ExAws.S3.html)
- [ExAws HTTP client behaviour and Req integration](https://ex-aws.hexdocs.pm/ExAws.Request.HttpClient.html)
- [VersityGW v1.8.0](https://github.com/versity/versitygw/releases/tag/v1.8.0) and [POSIX backend](https://github.com/versity/versitygw/wiki/POSIX-Backend)
- [S3 POST policy conditions](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-HTTPPOSTConstructPolicy.html), [conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html), and [GetObject response overrides](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html)

These references inform the design; they are not evidence that QuickTrain's integration or an AWS deployment has been tested.
