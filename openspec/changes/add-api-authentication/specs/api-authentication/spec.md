## Purpose

Provide a one-time OIDC-to-bearer handshake and fail-closed API actor boundary before organization-owned product data is exposed through GraphQL.

## ADDED Requirements

### Requirement: OIDC exchange is one-time and client-bound
The system SHALL begin OIDC login with fresh server-generated state, nonce, PKCE material, and a separate proof returned only to the initiating client. Callback selection SHALL come only from trusted server configuration. Exchange SHALL require that client proof, the matching unexpired login transaction, the exact callback selected at begin, and a valid provider response. It SHALL allow only one claimant to consume a login transaction and issue a bearer session; a concurrent, later, failed, or interrupted claimant SHALL NOT make the transaction reusable.

#### Scenario: Login material is unpredictable and server selected
- **WHEN** an unauthenticated client begins OIDC login
- **THEN** the system returns fresh state and client proof, constructs the provider request from server-generated PKCE and nonce material, and does not accept caller-selected proof or callback material

#### Scenario: Login redemption is bound to the initiating client
- **WHEN** another client obtains a valid provider callback and state without the separate proof returned at begin
- **THEN** exchange rejects the request before provider redemption or session issuance

#### Scenario: Concurrent exchanges issue one session
- **WHEN** independent requests concurrently exchange the same valid login transaction
- **THEN** exactly one request may consume it and issue a bearer session

#### Scenario: Claimed transaction cannot be reopened
- **WHEN** an exchange fails or is interrupted after winning the one-time claim
- **THEN** a later request cannot return the transaction to a reusable state or issue a session from it

### Requirement: OIDC transport and unauthenticated admission are bounded
The system SHALL accept production OIDC begin, exchange, and provider callback requests only through authenticated encrypted transport after honoring forwarded scheme information solely from configured trusted proxies. Production callback configuration SHALL use HTTPS; exact loopback HTTP callbacks MAY be enabled only in development and test. Before persisting login state or contacting a provider, unauthenticated begin SHALL enforce configurable global and per-network-source request limits plus a cap on outstanding unexpired login transactions. Network-source identity SHALL use the direct peer or addresses supplied only by a configured trusted proxy, never an untrusted forwarding header.

#### Scenario: Insecure production flow is rejected
- **WHEN** a production begin, exchange, callback request, or configured non-loopback callback URI uses cleartext transport
- **THEN** the system redirects or rejects it before exposing proof material, contacting the provider, or issuing a session

#### Scenario: Sustained begin traffic is bounded
- **WHEN** unauthenticated begin traffic exceeds a configured request or outstanding-transaction limit
- **THEN** the system rejects excess requests before creating another login transaction or contacting the provider

### Requirement: OIDC account linking fails closed
The system SHALL link an external identity only by a verified canonical issuer and subject. It SHALL validate the provider response and require an existing external identity and its linked global user to be active before issuing a session. A new global user SHALL require a nonempty provider-verified email and SHALL receive a deterministic display name from nonblank provider name claims or the normalized email local part. Email and presentation claims SHALL NOT select, merge, reassign, or reactivate an existing account. Identity, email, status, or relationship conflicts SHALL fail closed without issuing a session.

#### Scenario: Existing issuer and subject resolve immutably
- **WHEN** a verified provider response matches an active external identity and active global user
- **THEN** exchange resolves that user without changing the identity's user relationship

#### Scenario: Inactive identity or user is denied
- **WHEN** the matched external identity or linked global user is not active
- **THEN** exchange fails without reactivating either record or issuing a bearer session

#### Scenario: New verified-email account gets a display name
- **WHEN** a new verified identity supplies an email but no nonblank name claim
- **THEN** exchange creates one active global user using the normalized email local part as the display name without using it to link another account

#### Scenario: Existing email is not an implicit link
- **WHEN** a new verified issuer and subject present an email already owned by another global user
- **THEN** exchange reports an account-linking conflict without linking, merging, reassigning, or issuing a session

### Requirement: Bearer sessions use one-way global-account identity
The system SHALL generate a high-entropy opaque bearer token, return its raw value only at issuance, and persist only a unique indexed one-way hash with required session metadata. Every session SHALL belong to an active global `User`; it SHALL authenticate only that account and SHALL NOT carry or grant organization authority. Authentication SHALL hash the presented token and resolve at most one unexpired, unrevoked session. Session expiry SHALL NOT exceed a configured maximum lifetime.

#### Scenario: Issued token is not persisted raw
- **WHEN** the system issues a bearer session
- **THEN** persistent state contains only its unique token hash and never the raw bearer token

#### Scenario: Session does not grant organization scope
- **WHEN** an active bearer session calls an organization-scoped action
- **THEN** the session authenticates the global user but supplies no organization authority

#### Scenario: Invalid session is denied
- **WHEN** a request presents a missing, malformed, unknown, expired, revoked, or user-inactive bearer token
- **THEN** authentication fails without selecting an organization or exposing protected data

### Requirement: Inactive session retention is bounded
The system SHALL automatically and idempotently delete expired or revoked session credential rows only after the later applicable expiry or revocation time plus a fixed retention interval. Cleanup SHALL preserve every unexpired and unrevoked session and SHALL NOT delete separately retained authentication-event evidence.

#### Scenario: Expired and revoked credentials are eventually removed
- **WHEN** inactive sessions pass their retention boundary
- **THEN** automatic cleanup removes their indexed token hashes without operator invocation

#### Scenario: Active credentials survive cleanup
- **WHEN** cleanup examines an unexpired and unrevoked session
- **THEN** it preserves the session and its bearer token remains eligible for ordinary authentication checks

### Requirement: Authenticated GraphQL resolves a fail-closed actor
The system SHALL set the active global user resolved from a valid bearer session as both the GraphQL and Ash actor. Every organization-scoped product action SHALL derive its target organization from the protected resource or explicit action relationship and separately require that organization to be active, the actor to have an active membership, and the actor to have the action's explicit capability. Missing scope or authorization SHALL fail closed without disclosing organization data.

#### Scenario: Active bearer session supplies the actor
- **WHEN** a request presents a valid bearer token for an active global user
- **THEN** GraphQL and Ash receive that user as the request actor

#### Scenario: Membership and capability remain required
- **WHEN** an authenticated user lacks an active membership or required capability for the target organization
- **THEN** the product action is denied without disclosing the protected resource

#### Scenario: Inactive organization is denied
- **WHEN** an authenticated member retains grants in an organization that is inactive
- **THEN** every caller-initiated organization-scoped action is denied without exposing protected data

### Requirement: Public GraphQL surface is minimal and authorized
The system SHALL define an explicit public GraphQL allowlist. At this prerequisite stage it SHALL expose only OIDC begin and exchange root fields, both unauthenticated. `Session`, `OidcLoginTransaction`, and `ExternalIdentity` resources and credential or PII fields including token hashes, OIDC proof or verifier material, provider subjects, and raw provider claims SHALL be absent from public schema introspection and reads rather than relying only on sensitive-field metadata. Operational health SHALL remain available only at `/healthz`, GraphQL SHALL NOT expose a health field, and GraphiQL SHALL be restricted to development. Policy-disabled foundation fields, including broad user list, read, and creation operations, SHALL be absent rather than becoming available to every bearer-authenticated account.

#### Scenario: Unauthenticated schema has no bypass
- **WHEN** an unauthenticated client queries the GraphQL schema
- **THEN** no health, product, or foundation operation other than OIDC begin and exchange is available

#### Scenario: Authenticated account lacks implicit administration
- **WHEN** an ordinary authenticated account attempts a former policy-disabled foundation operation
- **THEN** the field is absent and the account gains no global administration authority

#### Scenario: Authentication persistence is not introspectable
- **WHEN** any client introspects or directly queries public GraphQL
- **THEN** authentication resources and credential or PII fields are absent even when the request has a valid bearer token

#### Scenario: Operational health remains separate
- **WHEN** infrastructure requests `/healthz` outside development
- **THEN** health responds without exposing GraphQL data, while GraphiQL remains unavailable

### Requirement: First-manager bootstrap is operator-only
The system SHALL provide a responsibility-named operator command outside GraphQL that bootstraps the first organization manager from an exact active global-user UUID and normalized organization slug and name. In one transaction it SHALL create or resolve the active organization, active membership, organization role key `manager`, and role assignment. Repetition SHALL be idempotent only for the same relationship graph. Existing inactive facts, identity ownership mismatches, or conflicting organization or role facts SHALL fail without reactivation, reassignment, implicit product authority, or a partial graph. Concurrent identical invocations SHALL converge on the same graph. This authentication capability SHALL NOT define product or administration capability keys or grants; the change that introduces an authorized product action owns those facts.

#### Scenario: Operator bootstraps a fresh installation
- **WHEN** an operator invokes the command with one exact active user and nonconflicting organization facts
- **THEN** it establishes one active organization membership and manager role assignment without granting implicit product authority

#### Scenario: Matching bootstrap is repeatable
- **WHEN** sequential or concurrent invocations supply the same user UUID, organization identity, and fixed manager graph
- **THEN** they resolve one organization, membership, role, and assignment without duplicates

#### Scenario: Bootstrap conflict is atomic
- **WHEN** the requested user, organization, membership, role, or assignment conflicts with existing facts
- **THEN** the command reports the conflict without partially creating or reassigning access

### Requirement: OIDC login-state retention is bounded
The system SHALL reject expired or missing OIDC state and SHALL retain each login transaction through its expiry plus a fixed replay-rejection interval. Automatic cleanup SHALL idempotently remove only consumed, expired, or abandoned transactions beyond that cutoff and SHALL preserve unexpired login transactions.

#### Scenario: Expired retained state cannot be exchanged
- **WHEN** a client presents state after its transaction expires but before cleanup removes it
- **THEN** exchange rejects it and issues no bearer session

#### Scenario: Automatic cleanup preserves live state
- **WHEN** cleanup processes login transactions before and after their retention cutoffs
- **THEN** it removes only transactions beyond the cutoff without requiring operator invocation and preserves every unexpired transaction
