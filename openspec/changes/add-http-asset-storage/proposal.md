## Why

QuickTrain already owns asset authorization, integrity, immutable publication, and task export lifecycles, but its only working storage adapter is an in-memory test double. Make those features usable over HTTPS while keeping development, ordinary tests, and the full verification gate independent of live AWS services and credentials.

## What Changes

- Implement one S3 storage adapter for AWS S3 in production and the approved VersityGW filesystem-backed S3 service in development and integration tests. Select endpoints and credentials through configuration, preserving the existing in-memory adapter for ordinary tests.
- Add bounded browser uploads, verified immutable publication, authorized opaque downloads, and streaming publication of generated task exports through the existing Assets boundary. Enforce private storage through bucket/identity policies without upload ACLs, and return all form fields needed to satisfy each signed POST policy.
- Extend upload access descriptors with a signed multipart-form POST representation so the storage service can enforce the registered byte cap. **BREAKING:** clients using the S3 adapter must dispatch on the returned method and submit its form fields instead of assuming every upload is a raw PUT. Existing GET/PUT descriptors remain supported.
- Use short-lived signed GET access for direct S3/VersityGW downloads from an isolated storage host. Require attachment disposition, octet-stream content type, and no-store responses. Make `nosniff` additional protection where available, rather than a prerequisite that forces a download proxy. Keep lifecycle and authorization decisions in existing Ash actions and GraphQL as the only application API.
- Pin VersityGW, provide local HTTPS, preserve development files across service restarts, isolate integration-test storage, and add mise commands for service lifecycle and local storage verification.
- Define remote timeout behavior honestly: return bounded failures without granting readiness, tolerate an uncertain remote write outcome, and reverify complete immutable bytes on retry.
- Require operator-configured native S3 lifecycle rules for production staging objects and their versions, verified by the separate deployment check; keep sealed objects outside expiration rules.
- Make local protocol tests part of `mise run verify`; keep live AWS deployment checks separate and explicitly invoked against the exact configured production bucket and application identity, with isolated disposable probe objects. Local compatibility or a different bucket's results must not be represented as proof of that production configuration.

Explicit non-goals: a QuickTrain download-streaming route or required CDN/proxy, image inspection or inline rendering, spatial task answers, a new asset lifecycle or storage plugin framework, a separate filesystem application adapter, application-managed staging/credential/import maintenance, marketplace features, frontend work, and provisioning cloud infrastructure during development or CI.

## Capabilities

### New Capabilities

- `http-asset-storage`: A concrete S3 storage implementation, local VersityGW development and integration environments, bounded remote I/O, and honest provider qualification.

### Modified Capabilities

- `assets`: Support method-specific upload descriptors and isolated direct downloads with mandatory attachment/binary/cache controls and optional `nosniff`. Reconcile staging expiry with provider-native production retention while preserving finalizer claims and existing organization, attempt, and result authority.
- `task-results`: Reconcile export deadline failures with uncertain remote commits while preserving sealed snapshots, pending-asset retry rules, and verified publication.

## Impact

- Affects `QuickTrain.Assets.Storage`, the new S3 implementation, embedded GraphQL storage-access types, storage configuration, download delivery, and the existing task export storage integration.
- Adds only stable, pinned S3 client/signing dependencies required by the selected implementation, plus a pinned VersityGW development container and local certificate setup. Use maintained signing/client functions rather than implementing AWS request signing.
- Extends Compose and mise tooling and documents the local/provider contract. No new business resource or database migration is expected; any necessary persistence change must be justified in the design and generated through Ash.
- Remains within the reusable backend foundation: one global User, optional membership for existing task-worker routes, and fail-closed scoped authorization. Detailed media still requires its own change before `add-project-task-media` can proceed; this change provides only the real opaque-storage prerequisite.

The user approved HTTP storage, cloud-independent development/tests, VersityGW, and optional nosniff for isolated direct downloads. The runtime implementation and pinned gateway protocol checks are implemented. Local verification evidence is recorded in the design; AWS deployment qualification has not been performed.

## Approved download decision

The approved contract uses direct signed downloads and makes `nosniff` optional on the isolated storage endpoint. A transfer route or proxy solely to inject that header is outside this change.

S3 supports signed overrides for Content-Disposition, Content-Type, and Cache-Control, but not X-Content-Type-Options. Attachment disposition directs normal navigation toward downloading; it is not equivalent to the strict script/style MIME checks supplied by `nosniff`. A separate storage origin also does not make it safe to include uploaded bytes as scripts in the application. The contract therefore keeps files as opaque downloads, isolates the storage hostname from application credentials and cookies, and prohibits clients from treating storage as an executable-content or preview source. Providers that already supply `nosniff` retain it. Inline media remains a separate design decision.

Keeping `nosniff` mandatory would instead require a compatible response-header layer, such as a CDN/proxy or an application streaming endpoint. That remains viable if the additional browser protection is required, but would add infrastructure or make QuickTrain carry download traffic.

Implementation must reconcile the existing storage module documentation and README with the accepted contract. The main Assets spec remains unchanged until this change is applied and synchronized.

References: [S3 GetObject response overrides](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html), [attachment disposition](https://www.rfc-editor.org/rfc/rfc6266.html#section-4.2), and [Fetch nosniff checks](https://fetch.spec.whatwg.org/#should-response-to-request-be-blocked-due-to-nosniff).
