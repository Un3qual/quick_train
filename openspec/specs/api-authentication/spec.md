# API Authentication Specification

## Purpose

Provide a one-time OIDC-to-bearer handshake and fail-closed API actor boundary before organization-owned product data is exposed through GraphQL.

## Requirements

### Requirement: OIDC exchange is one-time and client-bound
The system SHALL begin OIDC login with fresh server-generated state, nonce, PKCE material, and a separate proof returned only to the initiating client. Callback selection SHALL come only from trusted server configuration and SHALL target a client-owned callback rather than a QuickTrain callback ingress. The client callback SHALL receive the provider authorization response and hand its code and state to exchange together with the separate client proof. QuickTrain SHALL expose no provider-callback route. Exchange SHALL require that client proof, the matching unexpired login transaction, the provider code and state, the exact callback selected at begin, and a valid provider response. It SHALL allow only one claimant to consume a login transaction and issue a bearer session; a concurrent, later, failed, or interrupted claimant SHALL NOT make the transaction reusable.

#### Scenario: Login material is unpredictable and server selected
- **WHEN** an unauthenticated client begins OIDC login
- **THEN** the system returns fresh state and client proof, constructs the provider request from server-generated PKCE and nonce material, and does not accept caller-selected proof or callback material

#### Scenario: Login redemption is bound to the initiating client
- **WHEN** another client obtains a valid provider response code and state without the separate proof returned at begin
- **THEN** exchange rejects the request before provider redemption or session issuance

#### Scenario: Client-owned callback hands off to exchange
- **WHEN** the provider redirects a valid authorization response to the trusted callback selected at begin
- **THEN** the client submits that code and state with its separate proof to GraphQL exchange, and QuickTrain completes no login through a separate callback route

#### Scenario: Concurrent exchanges issue one session
- **WHEN** independent requests concurrently exchange the same valid login transaction
- **THEN** exactly one request may consume it and issue a bearer session

#### Scenario: Claimed transaction cannot be reopened
- **WHEN** an exchange fails or is interrupted after winning the one-time claim
- **THEN** a later request cannot return the transaction to a reusable state or issue a session from it

### Requirement: Authentication transport and unauthenticated admission are bounded
The system SHALL accept production OIDC begin and exchange requests only through authenticated encrypted transport after honoring forwarded scheme information solely from configured trusted proxies. It SHALL hard-reject cleartext exchange requests before provider contact, proof exposure, or session issuance and SHALL NOT redirect them. A proof-free cleartext begin request MAY instead be redirected to encrypted transport, but only before creating or returning state, proof, or provider request material. Every production request presenting a bearer credential SHALL pass the same trusted-proxy-aware encrypted-transport check and SHALL be hard-rejected without redirect before token hashing or lookup, GraphQL parsing, or action dispatch. Every response carrying OIDC state, client proof, provider request material, or a raw bearer token SHALL include `Cache-Control: no-store`. Production client-callback configuration, the configured provider issuer, and every discovered authorization, token, or key endpoint used by the OIDC flow SHALL use HTTPS and SHALL be rejected before provider contact otherwise; exact loopback HTTP client callbacks MAY be enabled only in development and test, but provider endpoints receive no such exception. Before persisting login state or contacting a provider, unauthenticated begin SHALL enforce configurable global and per-network-source request limits plus a cap on outstanding unexpired login transactions. Network-source identity SHALL use the direct peer or addresses supplied only by a configured trusted proxy, never an untrusted forwarding header.

#### Scenario: Cleartext exchange is rejected
- **WHEN** a production exchange request uses cleartext transport
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

#### Scenario: Insecure client-callback configuration is rejected
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

### Requirement: Session validity is independent of physical retention
The system SHALL reject expired, revoked, and inactive-account sessions regardless of whether their database rows remain. Automatic credential deletion is deferred to `restore-operator-bootstrap-and-maintenance`; credential rows currently remain stored.

#### Scenario: Expired credentials remain in storage
- **WHEN** a client presents an expired stored bearer credential
- **THEN** authentication rejects it without requiring physical deletion

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
The system SHALL define an explicit public GraphQL allowlist through AshGraphQL. OIDC begin and exchange SHALL be unauthenticated GraphQL mutations generated from typed generic Ash actions; they SHALL NOT be manual Absinthe fields or resolvers. Trusted network-source identity SHALL enter the begin action through Ash request context and SHALL NOT be accepted as a public GraphQL input. Because GraphQL requires a query root, this prerequisite stage SHALL expose one scalar, read-only `apiVersion` query and no application read. `Session`, `OidcLoginTransaction`, and `ExternalIdentity` resources and credential or PII fields including token hashes, OIDC proof or verifier material, provider subjects, and raw provider claims SHALL be absent from public schema introspection and reads rather than relying only on sensitive-field metadata. Operational health SHALL remain available only at `/healthz`, GraphQL SHALL NOT expose a health field, and GraphiQL SHALL be restricted to development. Policy-disabled foundation fields, including broad user list, read, and creation operations, SHALL be absent rather than becoming available to every bearer-authenticated account.

#### Scenario: Unauthenticated schema has no bypass

- **WHEN** an unauthenticated client queries the GraphQL schema
- **THEN** the query root contains only `apiVersion`, the mutation root contains only OIDC begin and exchange, and no health, product, account, or authentication-persistence operation is available

#### Scenario: OIDC operations use mutation semantics

- **WHEN** a client begins or exchanges an OIDC login through GraphQL
- **THEN** it invokes a typed generic Ash action through the mutation root, with begin receiving its trusted network source only from Ash request context

#### Scenario: Authenticated account lacks implicit administration
- **WHEN** an ordinary authenticated account attempts a former policy-disabled foundation operation
- **THEN** the field is absent and the account gains no global administration authority

#### Scenario: Authentication persistence is not introspectable
- **WHEN** any client introspects or directly queries public GraphQL
- **THEN** authentication resources and credential or PII fields are absent even when the request has a valid bearer token

#### Scenario: Operational health remains separate
- **WHEN** infrastructure requests `/healthz` outside development
- **THEN** health responds without exposing GraphQL data, while GraphiQL remains unavailable

### Requirement: Operator onboarding is deferred
The system SHALL NOT expose a first-manager bootstrap command or an automatic dataset/asset manager grant workflow in this development phase. Organization-scoped access SHALL continue to require explicit capability facts. Restoration is deferred to `restore-operator-bootstrap-and-maintenance`.

#### Scenario: An account has no explicit organization grant
- **WHEN** an active account requests a protected organization action
- **THEN** authorization denies access even if the account holds a role named manager

### Requirement: OIDC expiry and replay rejection do not depend on cleanup
The system SHALL reject expired or missing OIDC state and SHALL prevent reuse of exchanging or consumed transactions. Automatic physical deletion is deferred to `restore-operator-bootstrap-and-maintenance`; expired and consumed transactions currently remain stored.

#### Scenario: Expired stored state cannot be exchanged
- **WHEN** a client presents state after its stored transaction expires
- **THEN** exchange fails before contacting the provider
