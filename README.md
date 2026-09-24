# QuickTrain

QuickTrain is a backend-only Elixir template for enterprise applications. It keeps reusable
account, tenant, authorization, and enterprise identity foundations, with organization-owned
datasets, assets, versioned form definitions, and project-based task collection. It has no frontend.

## Deliberate model choices

- There is one global human `User` resource. There are no separate enterprise and consumer user
  tables and no principal abstraction.
- An `OrganizationMembership` relates a user to an enterprise organization. A consumer user may
  have no memberships, and the same account may be both an organization member and a consumer.
- Every bearer session requires an active global user account and carries no organization scope.
  Organization authority is checked from current relationships for each protected action. There
  are no guest sessions.
- Directory deprovisioning disables the enterprise membership while preserving the global user
  and independent consumer access.
- Authorization is fail-closed and organization-scoped through roles and capability keys.
- GraphQL is the only application API. No generated REST/JSON:API surface and no frontend are
  included. `/healthz` is an operational endpoint, not an application API.
- Generic revision history, audit logging, durable event delivery, generic integrations, and
  operation tracking are intentionally omitted.

## Included foundations

- `QuickTrain.Accounts`: global users, external OIDC identities, OIDC login transactions,
  account-required sessions, and authentication events.
- `QuickTrain.Organizations`: organizations and user memberships.
- `QuickTrain.Authorization`: organization roles, capability catalog, role grants, scoped role
  assignments, and optional decision evidence.
- `QuickTrain.EnterpriseIdentity`: provider-neutral connections, directories, users, groups,
  memberships, group-to-role mappings, and an adapter behaviour.
- `QuickTrain.Forms`: reusable typed input and question contracts, editable drafts, immutable
  publication, and copying to new numbered drafts. See the versioned-forms OpenSpec change for
  capability provisioning and authoring limits. Forms do not access dataset content or storage.
- `QuickTrain.Projects`: authored tasks, published form bindings, worker admission, and project lifecycle.
- `QuickTrain.Tasks`: leased work, typed drafts and immutable submissions, per-question review,
  scoped result reads, and immutable JSONL exports.
- `QuickTrainWeb.GraphQL.Schema`: an explicit allowlist of authentication, dataset, asset,
  form, project, and task operations with scoped authorization and paginated collections.

Within `QuickTrain.Tasks`, files follow their module namespaces: `Attempts` holds allocation,
leases, and project completion; `Responses` holds typed answers and submission; `Reviews` holds
review decisions; and `Exports` holds snapshots and JSONL generation. `Access` contains scoped
reads and authorization. The domain API remains in `tasks.ex`, with `Task`, `TaskInput`, and
shared `Access` and `Error` modules at the folder root. Background jobs live under `Workers`.

Collection requires explicit `projects.read`, `projects.manage`, `tasks.assign`, `tasks.review`,
and `tasks.results.read` grants for the relevant organizational roles. No production role gains
these capabilities automatically. Project workers use the configured member/external admission
route and always require an active global account. Image contracts are rejected at activation;
image rendering and spatial answers remain in the separate media change.

Task workers use the `task_maintenance` and `task_exports` Oban queues. Exports require a storage
adapter implementing streaming staging writes within the publication deadline and existing verification and
access contract. The in-memory adapter verifies byte generation and opaque access contracts in
tests; it does not provide HTTP delivery. Accumulated result counts are GraphQL decimal strings;
configured targets and published integer answers remain GraphQL integers.

## Toolchain

The repository is managed by [mise](https://mise.jdx.dev/) and pins stable releases in
`.mise.toml`: Erlang/OTP 29.0.4, Elixir 1.20.3 for OTP 29, Node.js 26.5.0, and OpenSpec 1.9.0.
Node and OpenSpec are development tools only; there is no JavaScript application or frontend.
Local PostgreSQL uses the official PostgreSQL 18.4 image.

```sh
mise install
mise run db.start
mise run setup
mise run test
mise run openspec.validate
mise run server
```

## Local HTTPS asset storage

Local storage uses the pinned official VersityGW v1.8.0 image with native TLS, a private
versioned bucket, and two persistent Docker volumes for current objects and version history.
Storage binds only to `https://127.0.0.1:55434`; run QuickTrain and consuming local clients on
`localhost` so their host-only cookies cannot reach storage.

```sh
mise run storage.setup
set -a
source .storage/local.env
set +a
PORT=4005 mise run server
```

Setup creates ignored development credentials in `.storage/local.env` and a development CA and
server certificate in `.storage/certs`. It starts the gateway, creates the bucket if needed,
enables and verifies versioning, and applies CORS for the explicit application origins. Rerunning
setup preserves credentials, certificate material, and objects. These credentials are only for
the local gateway; do not use cloud credentials here. The scripts pass the CA explicitly and
retain certificate-chain and hostname verification.

Install `.storage/certs/ca.pem` in your browser's trusted certificate store before making browser
uploads or downloads. On macOS, import it into the login keychain with Keychain Access, open its
Trust settings, and explicitly trust this development CA. Browsers with a separate certificate
store need the CA imported there too. Restart the browser if needed. Setup does not modify your
machine's trust store. Keep the CA private key and server private key in the ignored directory;
only the CA certificate is installed as trusted. Expired or incomplete certificate material
requires an explicit repair or regeneration followed by updating browser trust.

The generated environment declares application hosts as `["localhost"]` and cookie Domain scopes
as `[]`, meaning every application cookie is host-only. It permits browser `GET`, `HEAD`, and `POST`
from `http://localhost:4005`. Add the exact origins of consuming frontends to
`QUICK_TRAIN_STORAGE_CORS_ORIGINS_JSON` in `.storage/local.env`, then rerun setup. Local origins must
use `localhost`, with an explicit scheme and the actual client port. Never send application cookies
or bearer tokens to storage; use `credentials: "omit"` and `referrerPolicy: "no-referrer"` for fetches.
CORS controls browser access and does not authorize uploads or downloads.

Use `mise run storage.stop` and `mise run storage.start` to stop and restart only storage. Both
current objects and earlier versions survive restart. `mise run db.stop` stops only PostgreSQL.
Set `QUICK_TRAIN_STORAGE_PORT` before the first setup to choose another storage port; afterward,
change both the port and endpoint in `.storage/local.env` together. Do not run `docker compose down
--volumes` against development data. `mise run storage.test` creates its own disposable gateway,
credentials, certificate, and volumes and removes only that run's resources.

## OpenSpec workflow

OpenSpec is the source of truth for durable specifications and implementation plans. Its core
Codex skills are stored in `.agents/skills`, while project context and artifact rules live in
`openspec/config.yaml`.

Start a change in Codex with `$openspec-propose "describe the change"`, review the generated
artifacts, then use `$openspec-apply-change` to implement it and `$openspec-archive-change` after
verification. Run `mise exec -- openspec list --json` to inspect active changes from the terminal.

GraphQL is available at `POST http://localhost:4000/graphql`. Begin selects a client-owned
callback by configured key; QuickTrain intentionally exposes no provider callback route:

```graphql
mutation {
  beginOidcLogin(callbackKey: "desktop") {
    authorizationUri
    state
    clientProof
    expiresAt
  }
}
```

After the provider redirects `code` and `state` to that client callback, the initiating client
submits them with the separate `clientProof`:

```graphql
mutation {
  exchangeOidcLogin(code: "provider-code", state: "state", clientProof: "client-proof") {
    token
    sessionId
    expiresAt
  }
}
```

Responses containing login material use `Cache-Control: no-store`. Present the returned token as
`Authorization: Bearer <token>` on later requests. `/healthz` remains the separate operational
health endpoint, and `/graphiql` exists only in development.

Stop the local database with `mise run db.stop`. The database is published on port `55433` by
default so it does not collide with a system PostgreSQL installation; override
`QUICK_TRAIN_POSTGRES_PORT` if needed.

## Authentication and secrets

Set `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, and `OIDC_CALLBACKS_JSON` to enable OIDC.
The callback value is a JSON object from stable client key to exact client-owned callback URI. The
issuer and every discovered authorization, token, and key endpoint must use HTTPS. Production
callbacks must also use HTTPS; exact loopback HTTP callbacks are accepted only in development and
test. Discovery is validated before any discovered endpoint is contacted.

OIDC begin uses server-generated state, nonce, S256 PKCE, and a separate client redemption proof.
Only proof hashes, state/nonce hashes, and exchange-required verifier material are persisted. Raw
bearer tokens are returned once and only their unique SHA-256 hashes are stored. Existing accounts
are linked exclusively by the verified issuer and subject, never by email.

`TRUSTED_PROXY_IPS` is the comma-separated list of direct proxy IPs allowed to supply forwarded
scheme and client-address headers. The default production endpoint uses an HTTP listener behind a
TLS-terminating proxy, so production deployments must configure the proxy's direct IP and must
overwrite or reject client-supplied forwarding headers. A trusted proxy request without a final
`X-Forwarded-Proto` value fails closed. Direct production TLS requires separately configuring the
Phoenix HTTPS listener and certificates. The authentication defaults live in `config/config.exs`.
Deployments may override them with
`OIDC_BEGIN_WINDOW_MS`, `OIDC_BEGIN_GLOBAL_LIMIT`, `OIDC_BEGIN_NETWORK_LIMIT`,
`OIDC_OUTSTANDING_LIMIT`, `OIDC_TRANSACTION_TTL_SECONDS`, and
`HUMAN_SESSION_MAX_LIFETIME_SECONDS`.

Implement `QuickTrain.EnterpriseIdentity.Adapter` for the selected enterprise identity provider.

## Dataset and asset configuration

Dataset and asset access requires explicit organization-scoped capabilities. Operator manager
setup and grant helpers are deferred; basic Ash organization, membership, role, and capability
actions remain available. Tests compose these primitives in test-only fixtures.

`QuickTrain.Assets.Storage.S3` serves local VersityGW and production AWS S3 through explicit
runtime configuration. Unconfigured storage fails closed with `storage_not_configured`; partial
or invalid declarations fail startup. Ordinary tests retain the in-memory adapter, whose token
URLs are test doubles rather than HTTP endpoints. There is no ambient AWS credential lookup.

Files are opaque downloads: size and SHA-256 are verified, but the declared media type is
untrusted and no file parsing or image inspection occurs. Direct signed GET responses require
`Content-Disposition: attachment`, `Content-Type: application/octet-stream`, and
`Cache-Control: no-store`. `X-Content-Type-Options: nosniff` is welcome when supplied by the
provider but is optional on the isolated storage host. Storage cannot share an application
hostname or receive application cookies through a parent Domain scope. Attachment and host
isolation do not reproduce nosniff's script/style protections: never embed uploaded bytes as
scripts, styles, or inline previews. Inline media remains deferred.

Upload clients must dispatch on the descriptor's `method`. Select these fields from the
registration's `uploadAccess`:

```graphql
uploadAccess {
  method uri headers formFields fileField maxBytes expiresAt cacheControl referrerPolicy
}
```

For `POST`, decode the `formFields` JSON scalar string, copy every field unchanged, and append
the file last under `fileField`. The registered cap applies to file bytes, excluding multipart
overhead. Do not replace the signed object Content-Type field with the multipart request header;
let the browser's encoder supply its boundary:

```js
const form = new FormData();
for (const [name, value] of Object.entries(JSON.parse(access.formFields))) {
  form.append(name, value);
}
form.append(access.fileField, file);
const response = await fetch(access.uri, {
  method: "POST",
  body: form,
  credentials: "omit",
  referrerPolicy: "no-referrer",
});
if (!response.ok) throw new Error("Upload failed");
```

Existing `PUT` descriptors remain supported: send the raw file and descriptor headers instead
of a form. Read access uses `GET` without upload fields. Finalize after a successful upload;
only verified assets become ready. Treat URIs and form fields as short-lived secrets: do not
log them or persist them in analytics, and never forward QuickTrain authorization headers.
Use `no-referrer` for both fetches and download links and omit application credentials.

Publication pins a staging version, checks complete bytes, conditionally writes the immutable
canonical object, and rechecks its bytes and delivery metadata. The operation deadline bounds
local work and cleans private spool files. A complete remote write can finish after a lost
response or timeout; that failure does not make the asset ready. A retry re-verifies content
under a current claim. Exports retain their sealed snapshot and pending asset under the existing
expiry/replacement rules, so retries do not silently include later submissions.

The default asset staging lifetime is one hour. Open imports also expire after one hour and accept
at most 10,000 rows, 100 fields per row, 256 KiB of scalar data per row, 64 KiB per text value, and
512 KiB per request. Import row jobs have eight bounded attempts. Oban prunes terminal jobs
after one day. All GraphQL collections use bounded keyset-paginated Relay connections.

Production additionally requires `DATABASE_URL` and `SECRET_KEY_BASE`; the other runtime settings
are documented in `.env.example`.

## Production storage qualification

Provision one private, versioned AWS S3 bucket for each deployment. Set Object Ownership to
`BucketOwnerEnforced`, enable all four S3 Block Public Access settings, and use the bucket's
regional HTTPS endpoint. The application identity needs `s3:GetObject`, `s3:GetObjectVersion`,
and `s3:PutObject` for the normal `assets/staging/*` and `assets/sealed/*` resources. Scope access
to this bucket, require conditional writes to sealed objects, and deny the application identity
both `s3:DeleteObject` and `s3:DeleteObjectVersion` for sealed objects. Do not grant ACL-setting,
bucket-administration, or cleanup privileges to the application. Uploads deliberately omit ACLs.

AWS supports enforcing `If-None-Match` through the `s3:if-none-match` policy condition. Apply
these deny statements to the application principal in the bucket policy, alongside its narrowly
scoped allow statements; replace the account, role, and bucket placeholders. Do not apply the
application deletion denial to the separate operator identity used for probe cleanup. See
[AWS conditional-write enforcement](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes-enforce.html).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireConditionalSealedWrites",
      "Effect": "Deny",
      "Principal": {"AWS": "arn:aws:iam::ACCOUNT:role/APPLICATION_ROLE"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/assets/sealed/*",
      "Condition": {"StringNotEquals": {"s3:if-none-match": "*"}}
    },
    {
      "Sid": "DenyApplicationSealedDeletion",
      "Effect": "Deny",
      "Principal": {"AWS": "arn:aws:iam::ACCOUNT:role/APPLICATION_ROLE"},
      "Action": ["s3:DeleteObject", "s3:DeleteObjectVersion"],
      "Resource": "arn:aws:s3:::BUCKET/assets/sealed/*"
    }
  ]
}
```

Provision this simple lifecycle configuration through your infrastructure tooling. The separate
delete-marker rule is required. Both day counts must strictly exceed the sum of maximum staging
lifetime, upload-access lifetime, publication-claim lifetime, and publication operation budget.
The current defaults total 4,650 seconds, so one day qualifies. `storage.check` derives the window
from the running configuration and rejects one day if changed lifetimes make it unsafe.

```json
{
  "Rules": [
    {
      "ID": "staging-expiration",
      "Status": "Enabled",
      "Filter": {"Prefix": "assets/staging/"},
      "Expiration": {"Days": 1},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 1}
    },
    {
      "ID": "staging-delete-markers",
      "Status": "Enabled",
      "Filter": {"Prefix": "assets/staging/"},
      "Expiration": {"ExpiredObjectDeleteMarker": true}
    }
  ]
}
```

Qualification accepts only enabled, unambiguous rules for the exact `assets/staging/` prefix,
with finite expiration ages and no retained-version count, tag/size filters, transitions, or
date-based expiration. Broader rules and any sealed-object expiration fail. Object Lock,
MFA Delete, and replication configurations also fail this qualification profile because they
can prevent staging versions from expiring. Native lifecycle cleanup is asynchronous; it is
neither an exact deletion deadline nor a hard storage quota. See
[AWS lifecycle interactions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-and-other-bucket-config.html).

Supply the exact deployment settings and application credentials through
`QUICK_TRAIN_STORAGE_PROFILE=aws`, `QUICK_TRAIN_STORAGE_ENDPOINT`, `QUICK_TRAIN_STORAGE_REGION`,
`QUICK_TRAIN_STORAGE_BUCKET`, `QUICK_TRAIN_STORAGE_ACCESS_KEY`, and
`QUICK_TRAIN_STORAGE_SECRET_KEY`; use `QUICK_TRAIN_STORAGE_SESSION_TOKEN` for temporary credentials.
Set `QUICK_TRAIN_STORAGE_ADDRESSING` to `path` or `virtual`; AWS buckets containing dots require
`path` because the standard wildcard certificate does not cover their virtual hostname.
AWS uses normal verified TLS trust by default; `QUICK_TRAIN_STORAGE_CA_FILE` optionally supplies
an explicit trusted CA file.

Declare every application/frontend hostname in `QUICK_TRAIN_STORAGE_APPLICATION_HOSTS_JSON`,
and all session-cookie Domain scopes in `QUICK_TRAIN_STORAGE_COOKIE_DOMAINS_JSON`. An explicit
`[]` cookie-domain list means all cookies are host-only. The actual storage hostname, including
the bucket prefix for virtual addressing, must differ from every application host and be outside
every declared cookie domain. For example, a `.example.com` cookie disqualifies
`storage.example.com`, even when the app is served from `app.example.com`. Another port on the
same hostname is insufficient. Keep these declarations aligned with all consuming clients.

The deployment check also requires explicit, separate operator credentials:
`QUICK_TRAIN_STORAGE_CHECK_ACCESS_KEY`, `QUICK_TRAIN_STORAGE_CHECK_SECRET_KEY`, and optional
`QUICK_TRAIN_STORAGE_CHECK_SESSION_TOKEN`. The operator needs the following read permissions on
the same bucket: `s3:GetBucketVersioning`, `s3:GetBucketOwnershipControls`,
`s3:GetBucketPublicAccessBlock`, `s3:GetLifecycleConfiguration`,
`s3:GetBucketObjectLockConfiguration`, `s3:GetReplicationConfiguration`,
`s3:GetBucketLocation`, and `s3:ListBucketVersions`. Missing inspection access fails the check.
Optional `s3:DeleteObjectVersion` access allows cleanup of this run's exact probe versions;
it is never added to the application identity. The
[AWS operation permission reference](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-with-s3-policy-actions.html)
lists these controls.

```sh
# Run with the deployment environment and its normal runtime configuration loaded.
MIX_ENV=prod mise run storage.check
```

The command does not provision or alter bucket configuration. It inspects the configured bucket,
then uses the runtime application credentials for actual ACL-free POST uploads, cap/field/signature
rejection, version-specific reads, checksum enforcement, conditional publication, signed-download
integrity and response headers, and denied unsigned access and sealed-object replacement/deletion.
It uses fresh UUIDs inside the normal staging and sealed key shapes, with no policy exceptions.
Only those run-owned keys and versions are eligible for operator cleanup. Failed cleanup is
reported as an exact key/version manifest; failed inventory reports the run's keys and fails
qualification rather than claiming complete cleanup. Keep the JSON report for manual cleanup
when operator deletion is unavailable.

`storage.check` uses server-side requests and reports `browser_cors: "not_checked"`.
Before enabling browser `fetch` transfers, separately configure and verify bucket CORS from
each consuming application's actual origin: allow `POST` uploads and any `GET`/`HEAD` access
the client uses, permit its request headers, and expose response headers the client reads.
Verify both successful transfers and rejection of an unapproved origin in the browser.
A `qualified` storage report alone does not establish browser compatibility; plain download
navigation does not require CORS.

The report identifies the endpoint, bucket, region, and a SHA-256 fingerprint of the application
access-key identifier, without printing credentials or signed access descriptors. Re-run the check
before enabling access whenever the target, application identity, lifetimes, or relevant bucket
controls change. A passing disposable bucket cannot qualify the runtime bucket. This command is
never called by setup, ordinary tests, or local verification. Local VersityGW compatibility and
AWS deployment qualification are separate results; AWS qualification remains unperformed until
this command succeeds against that deployment. Staging lifecycle retention does not replace the
deferred application maintenance work for database records or other accumulated resources.

## Project task collection

A project fixes its dataset/schema/form at creation. In draft, bind source fields and author
tasks using immutable revision IDs and ordered input slots. The cohort is derived from those
task inputs; there is no separate enrollment or group copy. Activation freezes that configuration, one submission
target per task, and project-wide skip rules. Allocation issues whole-form attempts with fixed
leases; review decisions change accepted results without requesting replacement work.

GraphQL exposes scoped `tasks`/`task` and `taskResults`/`taskResult` reads, with paginated nested
evidence. Workers use the native `workBundle` read and status-only `attemptReceipt`. Project create/update,
task create/remove, binding/slot-policy/worker-access upserts and removals, and attempt start/release/cancel/submit
mutations use native Ash result/errors shapes. Child upserts take an `input` object and return
the affected child. Domain updates accept records; child removals accept the child record and
organization ID. Exports select complete accepted or audit results, seal
submitted-outcome membership, and publish deterministic JSONL through the Assets adapter. The header
contains shared form context; each subsequent record contains one result with its inputs, typed
answers, and pinned review history. Counts refer to results. Nested collections stream in pages.

This feature is unreleased. Its branch migration history is consolidated into one migration;
recreate local databases that used an earlier version of the branch. No data conversion is provided.

## Clean-database migration requirement

The authentication persistence migration deliberately establishes the target schema without a
legacy-data compatibility path. Existing local databases created from the earlier template must
be reset before applying it:

```sh
mise exec -- mix ecto.reset
mise exec -- env MIX_ENV=test mix ecto.reset
```

These commands destroy the corresponding local development or test database. Do not apply this
reset approach to a database containing production data; design a dedicated compatibility
migration first.

The authentication persistence migration is explicitly forward-only because one-way credential
hashes and issuer/subject identities cannot be reconstructed as the legacy schema.

## Verification

`mise run verify` first validates all OpenSpec artifacts in strict, non-interactive mode, then runs
formatting, boundary and dependency-cycle checks, static analysis, Dialyzer, Hex's security-advisory
and retired-package audit, a production compile, and the ordinary test suite, then runs the tagged
HTTPS storage suite in a separate BEAM invocation. Docker and local PostgreSQL must be available;
missing services fail explicitly. The storage suite uses disposable local credentials and never
requires cloud credentials. Run `mise run dependency.audit`
to check dependencies independently. Generate migrations and resource snapshots after
changing Ash resources:

```sh
mix ash.codegen describe_the_change
```

Review migrations before applying them.

## Deferred operator setup and maintenance

[restore-operator-bootstrap-and-maintenance](openspec/changes/restore-operator-bootstrap-and-maintenance/proposal.md)
is future work, to revisit after further organization onboarding and storage progress. No custom
periodic application maintenance jobs currently run. Production storage requires qualified native
bucket rules to expire staging objects, noncurrent versions, and expired delete markers after the
active-use safety window. Provider expiration is asynchronous: it supplies neither a hard storage
quota nor an exact cleanup deadline. Local development storage persists until explicitly reset.
Staging expiry still denies new access and finalization, and claim fencing remains enforced.
Expired authentication records and abandoned imports accumulate; abandoned imports keep their
idempotency keys. Cancelled or
exhausted import jobs may leave rows pending, and ordinary Oban pruning may remove their evidence.
Expiry, replay rejection, authorization, normal finalization, and row processing remain enforced.
Restore maintenance before relying on unattended operation with persistent data.
