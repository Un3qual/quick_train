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

### Requirement: Authentication transport and unauthenticated admission are bounded
The system SHALL accept production OIDC begin, exchange, and provider callback requests only through authenticated encrypted transport after honoring forwarded scheme information solely from configured trusted proxies. It SHALL hard-reject cleartext exchange and callback requests before provider contact, proof exposure, or session issuance and SHALL NOT redirect them. A proof-free cleartext begin request MAY instead be redirected to encrypted transport, but only before creating or returning state, proof, or provider request material. Every production request presenting a bearer credential SHALL pass the same trusted-proxy-aware encrypted-transport check and SHALL be hard-rejected without redirect before token hashing or lookup, GraphQL parsing, or action dispatch. Every response carrying OIDC state, client proof, provider request material, or a raw bearer token SHALL include `Cache-Control: no-store`. Production callback configuration, the configured provider issuer, and every discovered authorization, token, or key endpoint used by the OIDC flow SHALL use HTTPS and SHALL be rejected before provider contact otherwise; exact loopback HTTP callbacks MAY be enabled only in development and test, but provider endpoints receive no such exception. Before persisting login state or contacting a provider, unauthenticated begin SHALL enforce configurable global and per-network-source request limits plus a cap on outstanding unexpired login transactions. Network-source identity SHALL use the direct peer or addresses supplied only by a configured trusted proxy, never an untrusted forwarding header.

#### Scenario: Cleartext exchange and callback are rejected
- **WHEN** a production exchange or callback request uses cleartext transport
- **THEN** the system rejects it without redirecting, contacting the provider, exposing proof material, or issuing a session

#### Scenario: Cleartext begin exposes no login material
- **WHEN** a production begin request uses cleartext transport
- **THEN** the system rejects it or redirects only that proof-free request before creating or returning state, proof, or provider request material

#### Scenario: Cleartext bearer request is rejected before authentication
- **WHEN** a production GraphQL request presents a bearer credential over cleartext transport
- **THEN** the system rejects it without redirecting, hashing or looking up the token, parsing GraphQL, or dispatching an action

#### Scenario: Login and bearer material is not cacheable
- **WHEN** a response returns OIDC state, client proof, provider request material, or a newly issued raw bearer token
- **THEN** the response is marked `Cache-Control: no-store`

#### Scenario: Insecure callback configuration is rejected
- **WHEN** a configured production non-loopback callback URI uses cleartext transport
- **THEN** the system rejects the flow before creating login material or contacting the provider

#### Scenario: Insecure provider endpoint is rejected
- **WHEN** production configuration supplies a cleartext issuer or discovery returns a cleartext authorization, token, or key endpoint
- **THEN** the system rejects the flow before sending an authorization request, code, client credential, token, or verification-key request to that endpoint

#### Scenario: Sustained begin traffic is bounded
- **WHEN** unauthenticated begin traffic exceeds a configured request or outstanding-transaction limit
- **THEN** the system rejects excess requests before creating another login transaction or contacting the provider

### Requirement: OIDC account linking fails closed
The system SHALL link an external identity only by a verified canonical issuer and subject. It SHALL validate the provider response and require an existing external identity and its linked global user to be active before issuing a session. A new global user SHALL require a nonempty provider-verified email and SHALL receive a deterministic display name from nonblank provider name claims or the normalized email local part. Creation of that user and its issuer/subject identity SHALL be atomic and concurrency safe so a losing identity-uniqueness transaction cannot leave an unlinked user. Email and presentation claims SHALL NOT select, merge, reassign, or reactivate an existing account. Identity, email, status, or relationship conflicts SHALL fail closed without issuing a session.

#### Scenario: Existing issuer and subject resolve immutably
- **WHEN** a verified provider response matches an active external identity and active global user
- **THEN** exchange resolves that user without changing the identity's user relationship

#### Scenario: Inactive identity or user is denied
- **WHEN** the matched external identity or linked global user is not active
- **THEN** exchange fails without reactivating either record or issuing a bearer session

#### Scenario: New verified-email account gets a display name
- **WHEN** a new verified identity supplies an email but no nonblank name claim
- **THEN** exchange creates one active global user using the normalized email local part as the display name without using it to link another account

#### Scenario: Concurrent first login creates one account graph
- **WHEN** independent exchanges concurrently resolve the same previously unseen verified issuer and subject
- **THEN** they converge on one external identity and one linked global user, and any losing transaction leaves no additional unlinked user

#### Scenario: Existing email is not an implicit link
- **WHEN** a new verified issuer and subject present an email already owned by another global user
- **THEN** exchange reports an account-linking conflict without linking, merging, reassigning, or issuing a session

### Requirement: Bearer sessions use one-way global-account identity
The system SHALL generate a high-entropy opaque bearer token, return its raw value only at issuance, and persist only a unique indexed one-way hash with required session metadata. A session SHALL be issued only for an active global `User`; it SHALL authenticate only that account and SHALL NOT carry or grant organization authority. Authentication SHALL hash the presented token and resolve at most one unexpired, unrevoked session whose user remains active. Disabling a user SHALL make every otherwise valid session for that user immediately ineligible without requiring those session rows to be revoked or deleted. Session expiry SHALL NOT exceed a configured maximum lifetime.

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
The system SHALL automatically and idempotently delete expired or revoked session credential rows only after the later applicable expiry or revocation time plus a fixed retention interval. Cleanup SHALL preserve every unexpired and unrevoked session row, including one whose user has since been disabled, while ordinary authentication continues to require an active user. Cleanup SHALL NOT delete separately retained authentication-event evidence.

#### Scenario: Expired and revoked credentials are eventually removed
- **WHEN** inactive sessions pass their retention boundary
- **THEN** automatic cleanup removes their indexed token hashes without operator invocation

#### Scenario: Active credentials survive cleanup
- **WHEN** cleanup examines an unexpired and unrevoked session
- **THEN** it preserves the session row and ordinary authentication separately determines eligibility from session and current-user state

#### Scenario: Disabled-user credential is retained but denied
- **WHEN** cleanup examines an unexpired and unrevoked session whose user has been disabled
- **THEN** it preserves the session row while authentication rejects its bearer token

### Requirement: Authenticated GraphQL resolves a fail-closed actor
The system SHALL set the active global user resolved from a valid bearer session as both the GraphQL and Ash actor. The shared organization-capability authorization path SHALL derive its target organization from the protected resource or explicit action relationship and separately require the actor to remain active, that organization to be active, the actor to have an active membership, and the actor to have the action's explicit capability. An organization-scoped product action MAY use another authorization path only when the product capability that owns the action explicitly defines a named relationship-bound contract; such a path SHALL still require an active actor and active organization and SHALL NOT treat the bearer session alone as organization authority. Missing scope or authorization SHALL fail closed without disclosing organization data.

#### Scenario: Active bearer session supplies the actor
- **WHEN** a request presents a valid bearer token for an active global user
- **THEN** GraphQL and Ash receive that user as the request actor

#### Scenario: Membership and capability remain required
- **WHEN** an action uses organization-capability authorization and the authenticated user lacks an active membership or required capability for the target organization
- **THEN** the shared path denies the action without disclosing the protected resource

#### Scenario: Undefined alternative authorization is denied
- **WHEN** an organization-scoped action does not satisfy the shared organization-capability path and its owning product capability defines no other relationship-bound authorization contract
- **THEN** authentication alone grants no organization access and the action is denied without disclosing the protected resource

#### Scenario: Inactive organization is denied
- **WHEN** an authenticated member retains grants in an organization that is inactive
- **THEN** every caller-initiated organization-scoped action is denied without exposing protected data

#### Scenario: Disabled user is denied despite retained grants
- **WHEN** a disabled user retains an active membership and capability grant in an active organization
- **THEN** the shared capability check and every caller-initiated organization-scoped action deny access without exposing protected data

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
