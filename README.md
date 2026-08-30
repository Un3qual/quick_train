# QuickTrain

QuickTrain is a backend-only Elixir template for enterprise applications. It keeps reusable
account, tenant, authorization, and enterprise identity foundations while leaving product domains
and the frontend empty.

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
- `QuickTrainWeb.GraphQL.Schema`: an explicit public allowlist containing the read-only
  `apiVersion` query and OIDC begin and exchange mutations until product changes add their own
  authorized fields.

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
scheme and client-address headers. Leave it empty when Phoenix receives traffic directly. The
remaining `OIDC_*` and `HUMAN_SESSION_*` bounds are shown with defaults in `.env.example`.

Bootstrap the first organization manager from an existing active global-user UUID with the
operator-only command:

```sh
mise exec -- mix quick_train.bootstrap_first_manager \
  --user-id USER_UUID \
  --organization-slug acme-training \
  --organization-name "Acme Training"
```

The command creates or resolves only the organization, active membership, `manager` role, and
role assignment. It does not create capability keys or grants. Authentication retention runs at
minute 17 of every hour through Oban and removes only login state and inactive credential rows
beyond their configured cutoffs.

Implement `QuickTrain.EnterpriseIdentity.Adapter` for the selected enterprise identity provider.

Production additionally requires `DATABASE_URL` and `SECRET_KEY_BASE`; the other runtime settings
are documented in `.env.example`.

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
formatting, boundary and dependency-cycle checks, static analysis, Dialyzer, Hex's retired-package
audit, a production compile, and the test suite. Generate migrations and resource snapshots after
changing Ash resources:

```sh
mix ash.codegen describe_the_change
```

Review migrations before applying them.
