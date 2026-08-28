## Purpose

Provide a one-time OIDC-to-bearer handshake and fail-closed API actor boundary before organization-owned product data is exposed through GraphQL.

## ADDED Requirements

### Requirement: OIDC exchange is one-time
The system SHALL begin OIDC login by persisting hashed state, server-side PKCE material, an expiry, and a retention cutoff. Exchange SHALL atomically claim only an unexpired transaction in the `pending` state through a one-way transition to `exchanging` before contacting the provider. Only the winning claimant SHALL verify the provider response, resolve or create the global user and external identity under the configured linking policy, and issue a bearer session. Session issuance and the final `consumed` transition SHALL commit together. A concurrent, later, failed, or interrupted claimant SHALL NOT make the state reusable.

#### Scenario: Successful exchange issues one session
- **WHEN** a client exchanges a valid provider response for an unexpired pending login transaction
- **THEN** the system consumes the transaction and returns exactly one newly issued opaque bearer token

#### Scenario: Concurrent exchanges are fenced
- **WHEN** two independent requests simultaneously exchange the same valid OIDC state
- **THEN** exactly one request claims the transaction and every other request is rejected without issuing another session

#### Scenario: Failed claimant cannot reopen state
- **WHEN** the winning exchange fails or is interrupted after claiming the login transaction
- **THEN** a later request cannot return that transaction to pending or reuse it to issue a session

### Requirement: Bearer sessions use indexed one-way token identity
The system SHALL generate a high-entropy opaque bearer token, return its raw value only at issuance, and persist only its SHA-256 hash with required session metadata. Every issued session SHALL have a non-null token hash protected by a unique database identity and index. Authentication SHALL hash the presented token and resolve at most one matching session through that indexed identity.

#### Scenario: Issued token is not persisted raw
- **WHEN** the system issues a bearer session
- **THEN** persistent state contains only the token hash and never the raw bearer token

#### Scenario: Duplicate token hash is rejected
- **WHEN** session issuance attempts to persist a token hash already owned by another session
- **THEN** the unique identity rejects the write and the system does not expose an ambiguous bearer credential

### Requirement: Authenticated GraphQL resolves a fail-closed actor
The system SHALL accept only an unexpired and unrevoked session belonging to an active global user. It SHALL set that user as both the GraphQL and Ash actor. Organization-scoped actions SHALL additionally require an active membership in the target organization and the explicit capability for that action. Missing, malformed, unknown, expired, revoked, or inactive credentials SHALL fail closed without exposing organization data.

#### Scenario: Active bearer session supplies the actor
- **WHEN** a request presents a valid bearer token for an active unrevoked session and active user
- **THEN** GraphQL and Ash receive that global user as the request actor

#### Scenario: Invalid bearer session is denied
- **WHEN** a request presents no token or a malformed, unknown, expired, revoked, or inactive session token
- **THEN** every non-handshake GraphQL operation is denied without resolving an organization scope

#### Scenario: Membership and capability remain required
- **WHEN** an authenticated user lacks an active membership or the required capability for the target organization
- **THEN** the organization-scoped product action is denied without disclosing the protected resource

### Requirement: Unauthenticated API surface is minimal
The system SHALL expose only OIDC begin and exchange as unauthenticated GraphQL behavior. Operational health SHALL remain available only at `/healthz`; GraphQL SHALL NOT expose a health field. GraphiQL SHALL be restricted to development, and policy-disabled foundation operations SHALL NOT be reachable as unauthenticated alternatives.

#### Scenario: Health is not a GraphQL bypass
- **WHEN** an unauthenticated client queries the GraphQL schema
- **THEN** no GraphQL health field or non-handshake product or foundation operation is available

#### Scenario: Operational health remains separate
- **WHEN** infrastructure requests `/healthz`
- **THEN** the operational health endpoint responds without exposing GraphQL data or creating an application actor

### Requirement: OIDC login-state retention is bounded
The system SHALL reject expired or missing OIDC state and SHALL retain each login transaction through its expiry plus a fixed replay-rejection interval. A responsibility-named cleanup path SHALL idempotently delete consumed, expired, and abandoned transactions only after their retention cutoff. Cleanup SHALL NOT remove any unexpired pending or exchanging transaction.

#### Scenario: Expired retained state cannot be exchanged
- **WHEN** a client presents a login state after its transaction expires but before cleanup deletes it
- **THEN** the exchange is rejected and no bearer session is issued

#### Scenario: Cleanup removes only old login state
- **WHEN** cleanup processes transactions before and after their retention cutoffs
- **THEN** it deletes only transactions beyond the cutoff and preserves every unexpired pending or exchanging transaction

#### Scenario: Deleted state remains invalid
- **WHEN** a client presents state whose old transaction was removed after the retention cutoff
- **THEN** the exchange is rejected as unknown and no new transaction or session is inferred from it
