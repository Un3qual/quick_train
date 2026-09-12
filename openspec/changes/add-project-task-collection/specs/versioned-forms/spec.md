## MODIFIED Requirements

### Requirement: Organization-scoped form access
The system SHALL require an active authenticated account, active owning organization, active membership in that organization, and `forms.read` for general form inspection or `forms.manage` for authoring and publication. Each caller-initiated operation SHALL resolve its target within an explicit organization scope. The same checks SHALL apply to nested definitions and relationships. An identifier, a published state, or a capability in another organization SHALL NOT grant access. Organization membership SHALL remain optional for accounts generally. A non-member SHALL have no general form access; the only worker exception SHALL be the attempt-owned published-contract inspection defined below. Management capability SHALL authorize the result of a successful mutation without implicitly granting general read access.

#### Scenario: Authorized author creates a form
- **WHEN** an active member with `forms.manage` creates a form in their active organization
- **THEN** the system creates that organization's form and returns the mutation result

#### Scenario: Reader cannot publish
- **WHEN** an actor with `forms.read` and without `forms.manage` attempts to publish a version
- **THEN** the operation is denied without changing it

#### Scenario: Access fails closed across all read paths
- **WHEN** an unauthenticated actor, inactive account, inactive organization, inactive member, non-member, or actor without the required capability requests a form or nested definition through general form-inspection paths
- **THEN** the system denies access without exposing the definition or its existence through a different error for a foreign identifier

#### Scenario: Foreign child is supplied to an authorized mutation
- **WHEN** an authorized author supplies an option, question, requirement, or version belonging to another organization
- **THEN** the mutation fails without exposing or modifying that foreign record

## ADDED Requirements

### Requirement: Attempt-owned published-contract inspection
The system SHALL allow an eligible owner of an unexpired live task attempt in an active or paused project to inspect the exact published form contract pinned by that attempt through its work bundle without `forms.read` or organization membership. Every access SHALL check active account/organization, current worker audience route, absence of a block, and exact attempt ownership. The returned contract SHALL preserve published definition identities, typed constraints, options, labels, and authored presentation order, and identify which questions were offered. It SHALL grant no general form listing, draft access, other-version traversal, reverse organization relationships, or authoring action. It SHALL use bounded Relay connections with default 50/max 100 and SHALL cease on expiry, release, cancellation, submission, or lost eligibility. Publication semantics and the opaque-file boundary SHALL remain unchanged.

#### Scenario: An external worker reads their allocated contract
- **WHEN** an eligible non-member opens their current attempt work bundle
- **THEN** it includes that attempt's pinned published contract while general form APIs still deny access

#### Scenario: A worker changes the version identifier
- **WHEN** the same worker asks for an unallocated draft or different published version
- **THEN** the request fails without exposing its definitions
