## ADDED Requirements

### Requirement: Operator setup establishes explicit scoped authority
The system SHALL provide operator-only setup for an exact active global user and organization. Repeated identical setup SHALL converge without duplicates; inactive or conflicting facts SHALL fail atomically without reactivation or reassignment. Dataset and asset grants SHALL be explicit and organization-scoped, without wildcard or implicit authority.

#### Scenario: Identical operator setup is repeated concurrently
- **WHEN** operators request the same active manager graph and selected grants concurrently
- **THEN** they converge on one consistent result without partial or broader authority

### Requirement: Authentication retention removes only eligible state
The system SHALL periodically remove eligible expired or revoked credentials and consumed, expired, or abandoned OIDC state after defined retention intervals. It SHALL preserve live credentials and authentication-event evidence; authentication expiry and replay rejection SHALL remain independent of deletion.

#### Scenario: Retention processes live and expired credentials
- **WHEN** a bounded retention run examines both populations
- **THEN** it removes only records beyond their applicable retention boundary and live authentication behavior is unchanged

### Requirement: Staging cleanup preserves canonical content
The system SHALL periodically retire expired staging idempotently with provider-supported expiry or fencing guarantees. Cleanup SHALL serialize with finalization, account for prior or in-flight canonical publication before recording completion, reject stale transitions, and never remove canonical sealed content. Storage I/O SHALL occur outside database transactions.

#### Scenario: Publication completes after a finalizer loses its claim
- **WHEN** cleanup encounters a prior publication whose database transition did not complete
- **THEN** it waits through any remaining publication window and reverifies and accounts for canonical content before marking staging cleanup complete

### Requirement: Expired-open cleanup preserves immutable provenance
The system SHALL lock and recheck imports before deleting expired open imports and their unprocessed rows and unreferenced candidates. Successful cleanup SHALL release the abandoned batch identity; it SHALL NOT delete sealed imports or referenced revisions and records.

#### Scenario: Cleanup races finalization
- **WHEN** finalization seals an eligible import before cleanup obtains its lock
- **THEN** cleanup preserves the sealed import and all provenance

### Requirement: Terminal jobs cannot strand import progress
The system SHALL recover pending rows for discarded or cancelled import-row jobs through a durable callback or a bounded exact-worker reconciler. It SHALL atomically record sanitized failure under the row lock without creating a revision, skip terminal rows, drain backlogs without starvation, and preserve job evidence until recovery.

#### Scenario: Terminal jobs exceed one recovery page
- **WHEN** a backlog includes both already-terminal rows and pending rows
- **THEN** bounded recovery reaches every pending row before its evidence is pruned and races safely with late worker commits
