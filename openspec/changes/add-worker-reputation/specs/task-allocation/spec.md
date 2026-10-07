## MODIFIED Requirements

### Requirement: Project-worker eligibility preserves optional membership
Self-service allocation SHALL use the authenticated active global User and explicit active organization/project. An `organization_members` audience SHALL require active membership; `external_users` SHALL require the project's open external-access setting or explicit allow entry without requiring membership; `both` SHALL accept either route. Members SHALL also be able to qualify through the external route. An explicit block SHALL override every positive route. Anonymous sessions, inactive accounts/organizations/projects, and unmatched audiences SHALL fail closed. New issuance SHALL additionally enforce the project's frozen reputation admission rules and effective project suspension. Reputation-only admission failure SHALL NOT revoke authorization to otherwise permitted previously issued attempts or receipts. No separate worker identity, paid offer, or organization-management capability SHALL be inferred.

#### Scenario: An external user claims work without joining
- **WHEN** an active non-member requests work from an active project that permits open external access and satisfies its reputation admission rules
- **THEN** they can receive an attempt while remaining a non-member with no general project/dataset/form/asset browsing authority

#### Scenario: Blocks override both routes
- **WHEN** an active member also qualifies through an open external route but has a project block
- **THEN** allocation and live work-bundle access are denied

#### Scenario: One route is revoked while another remains
- **WHEN** membership ends for a worker who still qualifies through the project's external route
- **THEN** the worker remains eligible through that route unless explicitly blocked, while new issuance still requires reputation admission

#### Scenario: Reputation suspends only new work
- **WHEN** a worker receives a reputation-only suspension after being issued a live attempt
- **THEN** new issuance stops in that project while otherwise authorized bundle reads, saves, submission, and receipt access continue under their existing lifecycle and lease rules

### Requirement: Leases and allocation retries are durable
Attempts SHALL transition from claimed/assigned to in-progress on start or first save, and from a live state to submitted, expired, released, or cancelled. Terminal attempts SHALL never revive. Lease deadlines SHALL use server time, remain fixed after issuance, and be enforced after lock waits whether cleanup has run or not. Every fetch and assignment SHALL require a caller-supplied UUID request key. Invalid UUID input SHALL fail normal argument validation before selecting work or persisting collection changes. A successful allocation SHALL durably associate the validated request key with project, requesting actor, operation, and worker. An identical retry SHALL return the same attempt's current authorized result without a new lease; changed arguments with the same key SHALL conflict. Replaying an existing allocation SHALL apply current access authorization for that issued attempt, not the reputation admission gate for new work. A no-allocation result SHALL not be required to consume a key.

#### Scenario: A response is lost after allocation commits
- **WHEN** the caller retries the same allocation key and arguments
- **THEN** it receives the original attempt without creating another or extending its deadline

#### Scenario: Expiration cleanup is delayed
- **WHEN** an attempt deadline has passed but its expiration job has not run
- **THEN** work reads/saves/submission are denied and candidate-task allocation records its expiry and frees its live capacity before deciding whether to issue another attempt

#### Scenario: A suspension follows a lost allocation response
- **WHEN** issuance commits, its response is lost, and a reputation-only suspension is recorded before an identical retry
- **THEN** the retry returns the original currently authorized result without a new attempt or lease, while a fresh allocation request is denied new issuance

## ADDED Requirements

### Requirement: Reputation admission is atomic and shared by allocation routes
Pool fetch and direct assignment SHALL enforce the same frozen project reputation rules using the target worker's current project assessment and its jointly published automatic access reasons, with applicable manual reinstatement. Assignment permission or an audience allow entry SHALL NOT bypass a reputation restriction. Assessment/access publication, reinstatement, and issuance SHALL have a consistent transactional order: an issuance that commits before suspension retains its issued contract; issuance ordered after suspension SHALL fail without creating an attempt or presentation. An assessment known to require recalculation, including one past its next time-dependent invalidation or whose organization/global inputs changed, SHALL be refreshed for the decision or produce a retryable outcome after lock waits. Insufficient local history SHALL permit provisional participation while separately configured established organization/global entry requirements remain effective. Pending peer comparisons SHALL NOT be mistaken for stale computation or used for enforcement. These checks SHALL NOT alter task capacity, require replacement answers, or change existing review verdicts. A restriction SHALL affect only its project and SHALL remain separate from explicit account or audience blocks.

#### Scenario: A manager attempts to assign suspended work
- **WHEN** an authorized assignment manager targets a worker suspended by that project's reputation rules
- **THEN** the assignment creates no attempt or presentation

#### Scenario: Suspension races a new fetch
- **WHEN** the suspension and allocation transactions compete
- **THEN** either issuance commits first and is preserved, or suspension takes effect first and issuance is denied without partial work

#### Scenario: Another project remains available
- **WHEN** a worker is suspended in one project but satisfies another project's account, audience, and reputation rules
- **THEN** the first project's suspension alone does not prevent allocation in the second

#### Scenario: An explicit block follows a reputation-only suspension
- **WHEN** an authorized manager additionally blocks the worker through the existing project access override
- **THEN** the original block semantics still revoke existing-attempt access as well as new issuance

#### Scenario: A lock wait crosses the evidence expiration boundary
- **WHEN** allocation starts with a current assessment but its evidence window expires before the issuance check obtains its locks
- **THEN** allocation refreshes or retries rather than issuing or denying new work from the expired score
