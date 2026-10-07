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
Pool fetch and direct assignment SHALL evaluate the same frozen project reputation rules for each new issuance using the target worker's latest completed assessment inputs in every required scope and applicable manual reinstatement. Assignment permission or an audience allow entry SHALL NOT bypass a reputation restriction. A historical allow/deny result SHALL NOT replace this evaluation. Assessment publication, reinstatement, and issuance SHALL have a consistent transactional order across all consulted scopes: issuance ordered before a newly failing assessment retains its issued contract; issuance ordered after it SHALL evaluate the new inputs and fail if the rules deny access, without creating an attempt or presentation.

After lock waits, allocation SHALL recheck authorization, project state/configuration, the request key, latest completed project/organization/global inputs, and applicable reinstatement before evaluating admission. Pending recalculation or time-window expiry SHALL NOT withdraw completed inputs or produce a reputation-updating retry response. Changed completed broader inputs SHALL be used immediately without requiring a separate project decision refresh. Missing initial assessments SHALL be prepared in the ordinary request before its allocation transaction and locks, then conditionally published if still needed. A protection-input change invalidating a needed initial candidate SHALL release allocation locks before re-preparation. Evidence scans, peer comparisons, and full history calculations SHALL remain outside those locks; the locked evaluation SHALL use bounded completed metrics and frozen rules. The recorded decision SHALL identify the inputs actually used, and a denied request SHALL retain its outcome as scoped history without creating an attempt or latching that denial for subsequent requests.

Insufficient local history SHALL permit participation while separately configured established organization/global entry requirements remain effective. Pending peer comparisons SHALL NOT be mistaken for stale computation or used for enforcement. Reviewer-only signals SHALL NOT affect automatic admission through their values, missing evidence, or pending recalculation. These checks SHALL NOT alter task capacity, require replacement answers, or change existing review verdicts. A restriction SHALL affect only its project and SHALL remain separate from explicit account or audience blocks.

#### Scenario: Another calculation publishes during first-time preparation
- **WHEN** an initial request prepares a missing assessment outside allocation locks and a concurrent calculation publishes it before the request obtains those locks
- **THEN** the locked phase uses the completed assessment when evaluating admission rather than overwriting it with the candidate or scanning evidence again under the locks

#### Scenario: Authority is revoked during preparation
- **WHEN** initial reputation preparation begins while authorized but the relevant account, audience access, or assignment permission is revoked before issuance
- **THEN** locked revalidation denies issuance without an attempt or presentation, regardless of the prepared reputation result

#### Scenario: A correction invalidates a needed initial result
- **WHEN** locked revalidation finds that a correction or reinstatement invalidated a candidate and its required scope still has no completed assessment
- **THEN** it releases allocation locks before preparing again within the request, without moving the expensive calculation into the locked phase or waiting for a background scoring job

#### Scenario: A manager attempts to assign suspended work
- **WHEN** an authorized assignment manager targets a worker whose latest completed inputs and applicable reinstatement fail the project's reputation rules
- **THEN** the assignment creates no attempt or presentation and retains the denial as decision history

#### Scenario: A failing assessment races a new fetch
- **WHEN** a publication that establishes a failing reputation rule competes with allocation
- **THEN** either issuance is ordered first and preserved, or publication is ordered first and allocation evaluates the failing inputs and denies issuance without partial work

#### Scenario: A broader update commits during an allocation lock wait
- **WHEN** a global assessment changes before the waiting request obtains the locks protecting its admission evaluation
- **THEN** the request evaluates the newly completed global inputs and records that revision, even if its earlier preparation or the local project assessment used an older result

#### Scenario: A worker retries after broader reputation improves
- **WHEN** a worker denied by Project B later satisfies its broader entry requirement through newly completed reputation from other work and requests new work in B
- **THEN** both fetch and direct assignment use that improved assessment without a B-specific refresh job, retain the earlier denial as history, and permit issuance if the remaining rules and capacity allow it

#### Scenario: Another project remains available
- **WHEN** a worker fails one project's rules but satisfies another project's account, audience, and reputation rules
- **THEN** the first project's denial alone does not prevent allocation in the second

#### Scenario: An explicit block follows a reputation-only suspension
- **WHEN** an authorized manager additionally blocks the worker through the existing project access override
- **THEN** the original block semantics still revoke existing-attempt access as well as new issuance

#### Scenario: A lock wait crosses the evidence expiration boundary
- **WHEN** allocation starts with a current assessment but its evidence window expires before the issuance check obtains its locks
- **THEN** allocation evaluates the latest completed inputs after acquiring its locks, while the passed boundary triggers refresh without pausing work

#### Scenario: A required global input remains pending
- **WHEN** a previously eligible worker fetches or is assigned work while a contributing global signal awaits recalculation and the completed inputs still satisfy the rules
- **THEN** allocation continues using those completed inputs, subject to ordinary authorization and capacity checks, without returning a reputation-updating retry

#### Scenario: A completed assessment introduces a restriction
- **WHEN** recalculation publishes evidence that fails the project's configured rules after work was issued using previous completed inputs
- **THEN** subsequent issuance observes that failure while already-issued work remains available under its existing authorization and lease rules
