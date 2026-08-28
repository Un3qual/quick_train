## Purpose

Provide a one-time OIDC-to-bearer handshake and fail-closed API actor boundary before organization-owned product data is exposed through GraphQL.

## ADDED Requirements

### Requirement: OIDC exchange is one-time
The system SHALL begin OIDC login by generating state, nonce, a PKCE verifier, and a separate client-bound redemption secret server-side with a cryptographically secure random generator and at least 256 bits of entropy each. It SHALL persist a unique collision-checked hash of the state, a hash of the nonce, server-side verifier material, only a hash of the redemption secret, the selected trusted callback-configuration identity and exact callback URI, an expiry, and a retention cutoff; return the raw redemption secret only to the initiating client; never place that secret in the provider authorization request, callback URI, logs, or persistent state; derive only an S256 challenge; and reject caller-supplied state, nonce, verifier, challenge, redemption-secret, or callback URI material at begin. Callback URIs SHALL come only from trusted server configuration, and exchange SHALL reload and send the exact callback persisted by begin. Exchange SHALL require the initiating client's redemption secret and atomically claim only an unexpired transaction in the `pending` state whose redemption-secret hash matches in constant time, through a one-way transition to `exchanging` before contacting the provider. A missing or mismatched secret SHALL fail before provider exchange or session issuance. Only the winning claimant SHALL verify the provider response, including the nonce, resolve or create the global user and external identity under the configured linking policy, and issue a bearer session. Session issuance and the final `consumed` transition SHALL commit together. A concurrent, later, failed, or interrupted claimant SHALL NOT make the state reusable.

#### Scenario: Login proof material is unpredictable
- **WHEN** an unauthenticated client begins OIDC login
- **THEN** the server returns fresh unpredictable state and a separate redemption secret to that client plus an authorization request containing its server-generated nonce and server-derived S256 challenge, without accepting caller-selected proof material

#### Scenario: Successful exchange issues one session
- **WHEN** a client exchanges a valid provider response for an unexpired pending login transaction
- **THEN** the system consumes the transaction and returns exactly one newly issued opaque bearer token

#### Scenario: Callback selection is server pinned
- **WHEN** a client begins or exchanges login while attempting to supply a callback URI or alter the callback selected at begin
- **THEN** the system rejects caller callback material and uses only the exact trusted configured callback persisted on the login transaction for both authorization and exchange

#### Scenario: Login redemption is bound to the initiating client
- **WHEN** another client obtains a valid provider callback and state but does not possess the separate redemption secret returned only at begin
- **THEN** exchange rejects that client before contacting the provider or issuing a session, while never accepting caller-selected redemption proof at begin

#### Scenario: Concurrent exchanges are fenced
- **WHEN** two independent requests simultaneously exchange the same valid OIDC state
- **THEN** exactly one request claims the transaction and every other request is rejected without issuing another session

#### Scenario: Failed claimant cannot reopen state
- **WHEN** the winning exchange fails or is interrupted after claiming the login transaction
- **THEN** a later request cannot return that transaction to pending or reuse it to issue a session

### Requirement: OIDC account linking fails closed
The system SHALL support only the `issuer_subject_only` account-linking policy in the first release and SHALL reject missing or unknown policy configuration before login proceeds. It SHALL use the canonical verified issuer URI plus subject as the external identity, after validating the provider response signature, issuer, audience, nonce, and expiry. Before enabling canonical issuer-only lookup, the system SHALL migrate every legacy identity whose provider key is `oidc` to the one configured canonical issuer URI and SHALL abort without changing ambiguous or conflicting identities when configuration or issuer/subject relationships cannot be resolved uniquely. An existing external identity's user relationship SHALL be immutable, and exchange SHALL lock and require both that identity's lifecycle status and its linked global user's status to be exactly `active` in the same transaction that issues the session and consumes the login transaction. Provider claim refresh SHALL NOT change lifecycle status or reactivate a disabled identity or user. A new identity and global user SHALL begin active and require a non-empty provider-verified email. The new user's required display name SHALL use the first nonblank trimmed `name` or `preferred_username` claim and otherwise the normalized verified email's nonempty local part; that presentation value SHALL NOT participate in linking. Email SHALL NOT select, link, merge, or reassign an existing user. A disabled or unknown identity or user status SHALL fail closed with a non-disclosing authentication error and SHALL NOT issue a session. Email collisions and every issuer, subject, or user relationship conflict SHALL fail with `account_linking_conflict` and SHALL NOT issue a session.

#### Scenario: Existing issuer and subject resolve immutably
- **WHEN** a verified provider response contains an issuer and subject already linked to a global user
- **THEN** exchange resolves that user without changing the identity's `user_id`, even when refreshable profile claims changed

#### Scenario: Disabled external identity cannot log in
- **WHEN** a verified provider response matches an external identity whose status is disabled or otherwise not active while its global user remains active
- **THEN** exchange fails closed without refreshing the identity to active or issuing a bearer token, and the claimed login transaction remains unusable under the one-time exchange rules

#### Scenario: Disabled global user cannot receive a session
- **WHEN** a verified provider response matches an active external identity whose linked global user is disabled or otherwise not active
- **THEN** exchange fails closed without issuing a bearer token, and later reactivation cannot make a credential from that failed exchange usable

#### Scenario: Verified-email-only user gets a deterministic display name
- **WHEN** a new verified identity supplies a nonempty verified email but no nonblank `name` or `preferred_username` claim
- **THEN** exchange creates the active global user with the normalized email local part as its display name without using that value to link another account

#### Scenario: Legacy provider key migration is conflict safe
- **WHEN** an existing identity uses the legacy `oidc` provider key before canonical issuer-only lookup is enabled
- **THEN** the staged migration rewrites it only to the one configured verified issuer and aborts rather than guessing when configuration or identity relationships conflict

#### Scenario: Existing email is not an implicit link
- **WHEN** a verified issuer and subject are new but their verified email already belongs to another global user
- **THEN** exchange fails with `account_linking_conflict` without linking the identity, reassigning an account, or issuing a session

#### Scenario: Missing or unknown linking policy is rejected
- **WHEN** account-linking policy configuration is absent or is not `issuer_subject_only`
- **THEN** OIDC login cannot proceed and no identity, user, or session is created or changed

### Requirement: Legacy local accounts have an explicit identity transition
Before issuer/subject-only login becomes the account entry point, the system SHALL inventory every global user that has no external identity and SHALL provide a responsibility-named operator-only command outside GraphQL for reviewed legacy linking. The command SHALL consume an explicit mapping from an exact active global-user UUID to the configured canonical issuer URI and exact provider subject, SHALL lock the target user and identity uniqueness boundaries, SHALL be idempotent only when the same relationship already exists, and SHALL fail atomically when the user is missing or inactive, the issuer/subject belongs to another user, or the target user has a conflicting canonical identity. It SHALL NOT discover, select, merge, or reassign a user by email. Unmapped users and email collisions SHALL continue to fail closed under the ordinary OIDC exchange rules.

#### Scenario: Operator links an exact legacy user
- **WHEN** an operator supplies a reviewed mapping from one exact active legacy user UUID to an unclaimed canonical issuer and subject
- **THEN** the command creates or returns only that immutable active external-identity relationship without exposing a linking API through GraphQL

#### Scenario: Ambiguous legacy mapping is rejected
- **WHEN** a mapping targets an inactive or missing user, a subject owned by another user, or a user with a conflicting canonical identity
- **THEN** the command aborts without partially linking or changing any user and ordinary login continues to reject the conflict

### Requirement: Bearer sessions use indexed one-way token identity
The system SHALL generate a high-entropy opaque bearer token, return its raw value only at issuance, and persist only its SHA-256 hash with required session metadata. A bearer session SHALL authenticate the global account only and SHALL NOT carry or grant organization authority. Before enforcing global-account bearer resolution and non-null uniqueness, a staged data migration SHALL revoke every legacy session with a null token hash and assign each a distinct reserved `legacy-revoked:<session-id>` value that bearer-token hashing cannot produce, and SHALL revoke every legacy session with a non-null organization relationship. New issuance SHALL never set an organization relationship, and a database constraint SHALL permit a retained non-null legacy `organization_id` only when the session is revoked. Every issued session SHALL then have a non-null token hash protected by a unique database identity and index. Authentication SHALL hash the presented token and resolve at most one matching session through that indexed identity.

#### Scenario: Issued token is not persisted raw
- **WHEN** the system issues a bearer session
- **THEN** persistent state contains only the token hash and never the raw bearer token

#### Scenario: Duplicate token hash is rejected
- **WHEN** session issuance attempts to persist a token hash already owned by another session
- **THEN** the unique identity rejects the write and the system does not expose an ambiguous bearer credential

#### Scenario: Legacy null-hash sessions migrate safely
- **WHEN** the token-hash constraint is introduced on a database containing legacy sessions with null hashes
- **THEN** each legacy row is revoked and receives a unique reserved non-authenticating value before the non-null unique constraint is applied

#### Scenario: Legacy organization-scoped session cannot widen
- **WHEN** global-account bearer resolution is enabled on a database containing a non-null legacy session organization
- **THEN** that session is revoked before the resolver is enabled, its organization fact may remain only as revoked audit data, and no active or newly issued session can retain an organization relationship

### Requirement: Authenticated GraphQL resolves a fail-closed actor
The system SHALL accept only an unexpired and unrevoked global-account session belonging to an active global user. It SHALL set that user as both the GraphQL and Ash actor. Session metadata SHALL NOT select or authorize an organization; every caller-initiated organization-scoped action SHALL derive the target organization from the protected resource or explicit action relationship and additionally require that organization itself to be active, an active membership in that organization, and the explicit capability for that action. Missing, malformed, unknown, expired, revoked, or inactive credentials or organization scope SHALL fail closed without exposing organization data.

#### Scenario: Active bearer session supplies the actor
- **WHEN** a request presents a valid bearer token for an active unrevoked session and active user
- **THEN** GraphQL and Ash receive that global user as the request actor

#### Scenario: Invalid bearer session is denied
- **WHEN** a request presents no token or a malformed, unknown, expired, revoked, or inactive session token
- **THEN** every non-handshake GraphQL operation is denied without resolving an organization scope

#### Scenario: Membership and capability remain required
- **WHEN** an authenticated user lacks an active membership or the required capability for the target organization
- **THEN** the organization-scoped product action is denied without disclosing the protected resource

#### Scenario: Session does not grant organization scope
- **WHEN** an active global-account session calls an organization-scoped action
- **THEN** the action ignores any legacy session organization fact and authorizes only the organization derived from the protected resource or action relationship through current active membership and capability checks

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

### Requirement: Public GraphQL surface is minimal and authorized
The system SHALL expose only OIDC begin and exchange as unauthenticated GraphQL behavior. Operational health SHALL remain available only at `/healthz`; GraphQL SHALL NOT expose a health field. GraphiQL SHALL be restricted to development. Existing policy-disabled foundation fields, including broad user list, read, and creation operations, SHALL be removed from the public GraphQL schema rather than merely placed behind bearer authentication; they MAY remain internal Ash actions for tests and trusted operator workflows. No ordinary authenticated global account SHALL gain foundation administration authority merely by holding a bearer session.

#### Scenario: Health is not a GraphQL bypass
- **WHEN** an unauthenticated client queries the GraphQL schema
- **THEN** no GraphQL health field or non-handshake product or foundation operation is available

#### Scenario: Authenticated account lacks implicit foundation administration
- **WHEN** an ordinary authenticated global account attempts to list, read, or create users through a former policy-disabled foundation field
- **THEN** the field is absent from the public schema and the account cannot inspect global users or reserve another user's email

#### Scenario: Operational health remains separate
- **WHEN** infrastructure requests `/healthz`
- **THEN** the operational health endpoint responds without exposing GraphQL data or creating an application actor

#### Scenario: GraphiQL is absent outside development
- **WHEN** the router runs in a test or production environment
- **THEN** `/graphiql` is omitted or denied while `/healthz` remains available as the separate operational endpoint

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
