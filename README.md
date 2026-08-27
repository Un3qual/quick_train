# QuickTrain

QuickTrain is a backend-only Elixir template for enterprise applications. It keeps reusable
account, tenant, authorization, and enterprise identity foundations while leaving product domains
and the frontend empty.

## Deliberate model choices

- There is one global human `User` resource. There are no separate enterprise and consumer user
  tables and no principal abstraction.
- An `OrganizationMembership` relates a user to an enterprise organization. A consumer user may
  have no memberships, and the same account may be both an organization member and a consumer.
- Every session requires an active user account. Consumer sessions have no organization scope;
  organization-scoped sessions require an active membership. There are no guest sessions.
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
- `QuickTrainWeb.GraphQL.Schema`: a minimal GraphQL-only API ready for product fields.

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
mise run server
```

GraphQL is available at `POST http://localhost:4000/graphql`:

```graphql
query {
  health
}
```

Stop the local database with `mise run db.stop`. The database is published on port `55433` by
default so it does not collide with a system PostgreSQL installation; override
`QUICK_TRAIN_POSTGRES_PORT` if needed.

## Authentication and secrets

Set `OIDC_ISSUER`, `OIDC_CLIENT_ID`, and `OIDC_CLIENT_SECRET` to enable the supervised OIDC
discovery worker. `QuickTrain.Accounts.Oidc` exposes authorization URL and verified code exchange
functions through `oidcc`. Persist only hashes and short-lived transaction material; never store
raw browser session tokens.

Implement `QuickTrain.EnterpriseIdentity.Adapter` for the selected enterprise identity provider.

Production additionally requires `DATABASE_URL` and `SECRET_KEY_BASE`; the other runtime settings
are documented in `.env.example`.

## Verification

`mise run verify` runs formatting, boundary and dependency-cycle checks, static analysis,
Dialyzer, Hex's retired-package audit, a production compile, and the test suite. Generate migrations
and resource snapshots after changing Ash resources:

```sh
mix ash.codegen describe_the_change
```

Review migrations before applying them.
