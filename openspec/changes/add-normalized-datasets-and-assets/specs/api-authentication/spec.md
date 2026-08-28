## Purpose

Provide a one-time OIDC-to-bearer handshake and fail-closed API actor boundary before organization-owned product data is exposed through GraphQL.

## ADDED Requirements

### Requirement: OIDC exchange is one-time
The system SHALL begin OIDC login by generating state, nonce, and a PKCE verifier server-side with a cryptographically secure random generator and at least 256 bits of entropy each. It SHALL persist a unique collision-checked hash of the state, a hash of the nonce, server-side verifier material, an expiry, and a retention cutoff; derive only an S256 challenge; and reject caller-supplied state, nonce, verifier, or challenge material. Exchange SHALL atomically claim only an unexpired transaction in the `pending` state through a one-way transition to `exchanging` before contacting the provider. Only the winning claimant SHALL verify the provider response, including the nonce, resolve or create the global user and external identity under the configured linking policy, and issue a bearer session. Session issuance and the final `consumed` transition SHALL commit together. A concurrent, later, failed, or interrupted claimant SHALL NOT make the state reusable.

#### Scenario: Login proof material is unpredictable
- **WHEN** an unauthenticated client begins OIDC login
- **THEN** the server returns fresh unpredictable state and an authorization request containing its server-generated nonce and server-derived S256 challenge without accepting caller-selected proof material

#### Scenario: Successful exchange issues one session
- **WHEN** a client exchanges a valid provider response for an unexpired pending login transaction
- **THEN** the system consumes the transaction and returns exactly one newly issued opaque bearer token

#### Scenario: Concurrent exchanges are fenced
- **WHEN** two independent requests simultaneously exchange the same valid OIDC state
- **THEN** exactly one request claims the transaction and every other request is rejected without issuing another session

#### Scenario: Failed claimant cannot reopen state
- **WHEN** the winning exchange fails or is interrupted after claiming the login transaction
- **THEN** a later request cannot return that transaction to pending or reuse it to issue a session

### Requirement: OIDC account linking fails closed
The system SHALL support only the `issuer_subject_only` account-linking policy in the first release and SHALL reject missing or unknown policy configuration before login proceeds. It SHALL use the canonical verified issuer URI plus subject as the external identity, after validating the provider response signature, issuer, audience, nonce, and expiry. An existing external identity's user relationship SHALL be immutable. A new identity SHALL require a non-empty provider-verified email to create a new global user, but email SHALL NOT select, link, merge, or reassign an existing user. Email collisions and every issuer, subject, or user relationship conflict SHALL fail with `account_linking_conflict` and SHALL NOT issue a session.

#### Scenario: Existing issuer and subject resolve immutably
- **WHEN** a verified provider response contains an issuer and subject already linked to a global user
- **THEN** exchange resolves that user without changing the identity's `user_id`, even when refreshable profile claims changed

#### Scenario: Existing email is not an implicit link
- **WHEN** a verified issuer and subject are new but their verified email already belongs to another global user
- **THEN** exchange fails with `account_linking_conflict` without linking the identity, reassigning an account, or issuing a session

#### Scenario: Missing or unknown linking policy is rejected
- **WHEN** account-linking policy configuration is absent or is not `issuer_subject_only`
- **THEN** OIDC login cannot proceed and no identity, user, or session is created or changed

### Requirement: Bearer sessions use indexed one-way token identity
The system SHALL generate a high-entropy opaque bearer token, return its raw value only at issuance, and persist only its SHA-256 hash with required session metadata. Every issued session SHALL have a non-null token hash protected by a unique database identity and index. Authentication SHALL hash the presented token and resolve at most one matching session through that indexed identity.

#### Scenario: Issued token is not persisted raw
- **WHEN** the system issues a bearer session
- **THEN** persistent state contains only the token hash and never the raw bearer token

#### Scenario: Duplicate token hash is rejected
- **WHEN** session issuance attempts to persist a token hash already owned by another session
- **THEN** the unique identity rejects the write and the system does not expose an ambiguous bearer credential

### Requirement: Authenticated GraphQL resolves a fail-closed actor
The system SHALL accept only an unexpired and unrevoked session belonging to an active global user. It SHALL set that user as both the GraphQL and Ash actor. Every caller-initiated organization-scoped action SHALL additionally require the target organization itself to be active, an active membership in that organization, and the explicit capability for that action. Missing, malformed, unknown, expired, revoked, or inactive credentials or organization scope SHALL fail closed without exposing organization data.

#### Scenario: Active bearer session supplies the actor
- **WHEN** a request presents a valid bearer token for an active unrevoked session and active user
- **THEN** GraphQL and Ash receive that global user as the request actor

#### Scenario: Invalid bearer session is denied
- **WHEN** a request presents no token or a malformed, unknown, expired, revoked, or inactive session token
- **THEN** every non-handshake GraphQL operation is denied without resolving an organization scope

#### Scenario: Membership and capability remain required
- **WHEN** an authenticated user lacks an active membership or the required capability for the target organization
- **THEN** the organization-scoped product action is denied without disclosing the protected resource

#### Scenario: Inactive organization is denied
- **WHEN** an authenticated user retains an active membership and capability grant in an organization that is inactive
- **THEN** every caller-initiated organization-scoped action is denied without disclosing protected organization data

### Requirement: First-manager bootstrap is operator-only
The system SHALL provide a responsibility-named operator command, outside GraphQL, that bootstraps the first organization manager from an exact existing active global user. In one transaction it SHALL idempotently create or resolve the active organization, active membership, manager role assignment, and initial product-capability grants. Conflicting user or organization facts SHALL fail without leaving a partial authorization graph. No unauthenticated or ordinary authenticated API caller SHALL be able to invoke this bootstrap.

#### Scenario: Operator bootstraps a fresh installation
- **WHEN** an operator invokes the bootstrap command with one exact active user and non-conflicting organization facts
- **THEN** the command establishes one active manager authorization graph that can begin the authenticated product workflow

#### Scenario: Bootstrap conflict is atomic
- **WHEN** the requested slug, user identity, membership, role, or grants conflict with existing facts
- **THEN** the command reports the conflict without partially creating or reassigning organization access

### Requirement: Unauthenticated API surface is minimal
The system SHALL expose only OIDC begin and exchange as unauthenticated GraphQL behavior. Operational health SHALL remain available only at `/healthz`; GraphQL SHALL NOT expose a health field. GraphiQL SHALL be restricted to development, and policy-disabled foundation operations SHALL NOT be reachable as unauthenticated alternatives.

#### Scenario: Health is not a GraphQL bypass
- **WHEN** an unauthenticated client queries the GraphQL schema
- **THEN** no GraphQL health field or non-handshake product or foundation operation is available

#### Scenario: Operational health remains separate
- **WHEN** infrastructure requests `/healthz`
- **THEN** the operational health endpoint responds without exposing GraphQL data or creating an application actor

### Requirement: OIDC login-state retention is bounded
The system SHALL reject expired or missing OIDC state and SHALL retain each login transaction through its expiry plus a fixed replay-rejection interval. A responsibility-named cleanup path SHALL idempotently delete consumed, expired, and abandoned transactions only after their retention cutoff. Cleanup SHALL NOT remove any unexpired pending or exchanging transaction. The cleanup worker SHALL be registered with Oban's supported periodic scheduler at a fixed interval, and scheduled jobs SHALL be unique for an interval so retention occurs without manual invocation or overlapping cleanup runs.

#### Scenario: Expired retained state cannot be exchanged
- **WHEN** a client presents a login state after its transaction expires but before cleanup deletes it
- **THEN** the exchange is rejected and no bearer session is issued

#### Scenario: Cleanup removes only old login state
- **WHEN** cleanup processes transactions before and after their retention cutoffs
- **THEN** it deletes only transactions beyond the cutoff and preserves every unexpired pending or exchanging transaction

#### Scenario: Periodic scheduling invokes cleanup
- **WHEN** the application runs beyond the configured cleanup interval with expired retained transactions
- **THEN** Oban enqueues the cleanup worker without a caller or operator invoking it, and overlapping schedule ticks do not create concurrent duplicate cleanup jobs

#### Scenario: Deleted state remains invalid
- **WHEN** a client presents state whose old transaction was removed after the retention cutoff
- **THEN** the exchange is rejected as unknown and no new transaction or session is inferred from it
