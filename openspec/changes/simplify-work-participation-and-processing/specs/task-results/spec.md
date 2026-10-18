## MODIFIED Requirements

### Requirement: Result access is an explicit organization capability
Result and export operations SHALL require an active account, active owning organization, active membership, explicit organization/project scope, and `tasks.results.read`. Worker eligibility, ownership of one TaskParticipation, or another organization's permission SHALL not authorize result browsing. Reads SHALL return all effectively accepted question answers with exact project, form/schema version, task, revision, input, question, worker, and review provenance; they SHALL not select a canonical answer or synthesize consensus. Audit reads SHALL additionally expose submitted skips, pending/rejected outcomes, immutable review history, and expired/returned/cancelled TaskParticipations with their actual presentation. General results SHALL omit all unsubmitted draft payloads, including terminal drafts, account email/authentication secrets, storage credentials, and compensation fields. Result and export GraphQL responses, including access failures, SHALL inherit `Cache-Control: no-store` from the existing HTTP request-security boundary.

#### Scenario: Several accepted answers disagree
- **WHEN** a result reader inspects a question with different accepted answers
- **THEN** every accepted answer is returned with its own evidence and no answer is silently designated truth

#### Scenario: A worker requests the organization's results
- **WHEN** an external worker possessing a participation ID queries result collections
- **THEN** access fails without disclosing other workers or results

#### Scenario: Result operations pass through the HTTP boundary
- **WHEN** a caller requests result evidence, export status, or export download issuance through GraphQL
- **THEN** successful responses and authorization failures include `Cache-Control: no-store`

### Requirement: Result context makes answers interpretable
Collection context SHALL reuse canonical Forms, Datasets, Assets, and ProjectInputBinding resources without mirrored definitions or persisted copies. Published definitions SHALL be reached through scoped tasks, submitted outcomes, or owned work bundles; standalone collection-definition roots SHALL not be exposed. Each traversal SHALL recheck current worker or result authority and exact issued-input/bound-field membership. Caller-provided context alone SHALL confer no authority. Assets SHALL hide storage keys and operation claims through native field policies.

Result-only readers SHALL resolve question keys/prompts/families/renderers, complete typed constraints, selected options and labels, pinned presentation elements, input requirements, bound field identities, and exact source values without additional forms/datasets/assets grants. The at-most-one text, integer, decimal, selection, and annotation constraint objects SHALL retain original IDs and fields. Absent constraints SHALL remain distinguishable from present null bounds, and decimals SHALL remain exact. The export header SHALL include published question definitions with their fixed typed constraints and options, plus shared labels, presentation, and bindings. Interactive options and labels SHALL remain typed connections.

Every export header SHALL include the frozen Project's `review_mode`, either `automatic` or `manual`, separately from the export selection `mode`, either `accepted` or `audit`. An answered result's effective status SHALL follow its pinned human decision when present; without one, the frozen review mode SHALL distinguish automatic acceptance from pending manual review. Submitted skips SHALL remain skipped rather than inherit either answer default. Generation and retries SHALL use the sealed decision reference rather than the latest live review state. A result sealed without a decision SHALL retain its null decision reference, empty review history and frozen-mode interpretation after a later first human review. This SHALL require no synthetic review decision, separate stored verdict or copied review-mode snapshot column.

The complete pinned presentation sequence and per-participation input order SHALL explain the whole form. Nonempty exports SHALL include shared pinned form context once in the header. Each result SHALL embed its actual input order, exact revision identities, and bound typed values. For an exact input revision and binding, absence of a value in that input SHALL denote optional absence. Asset context SHALL include immutable identity/hash/size/media facts, never file bytes, credentials, or expiring URLs. New source downloads SHALL be separately authorized and short-lived. Worker bound-value reads and source-download authorization SHALL acquire Project protection and the owning TaskParticipation lock, retain them through the protected read/authorization, and use no shared Task write-conflicting lock. They SHALL recheck current eligibility, ownership, exact task/input membership, active or paused Project state, live participation state, and the database wall-clock lease deadline after lock waits. Storage descriptor issuance SHALL remain outside the database transaction with its authorized expiry bounded by the worker lease. No unbound-field or general organization browsing SHALL be authorized.

#### Scenario: A result-only reader interprets an answer
- **WHEN** a member with tasks.results.read reads choices, rankings, or labeled spans
- **THEN** its question, typed constraints, labels, exact inputs, and bound sources are available through scoped context while unrelated records remain denied

#### Scenario: A constraint is absent
- **WHEN** an integer question without a constraint record appears alongside a bounded Likert question
- **THEN** reads and exports retain their distinct renderers, bounds, and explicit constraint absence

#### Scenario: Instructions explain a response
- **WHEN** a pinned form includes headings, instructions, and bound-value placements
- **THEN** results preserve the original sequence and actual input order without substituting a newer form version

#### Scenario: An audit export explains automatic acceptance
- **WHEN** an audit snapshot selects an answered outcome in automatic mode with no human decision
- **THEN** its header identifies review_mode as automatic and the result is interpretable as accepted with a null decision reference and empty review history, without implying substantive human review

#### Scenario: An audit export explains pending manual review
- **WHEN** an audit snapshot selects an answered outcome in manual mode with no human decision
- **THEN** its header identifies review_mode as manual and the result is interpretable as pending with a null decision reference and empty review history

#### Scenario: A first human review follows export sealing
- **WHEN** an audit snapshot seals an automatically accepted answer without a human decision and its first human rejection commits before generation or retry
- **THEN** that sealed export keeps the null decision reference, empty review history and automatic acceptance interpretation, while a new snapshot can pin the rejection and use its verdict instead of the automatic default

#### Scenario: A review default does not accept a skip
- **WHEN** an audit export includes a submitted skip under either frozen review mode
- **THEN** the result remains skipped with no human decision rather than being interpreted as an accepted or pending answered outcome

#### Scenario: Independent workers read sources for the same Task
- **WHEN** eligible owners of separate live participations read their bound values or authorize source downloads for the same Task
- **THEN** each uses Project protection and its own participation guard without serializing through a shared Task write-conflicting lock
- **AND** each remains limited to its exact issued inputs, bound fields and lease

#### Scenario: A source request waits past its deadline
- **WHEN** an otherwise authorized source request obtains its participation lock after the database lease deadline
- **THEN** it returns no protected bound values or new download authorization, even if expiry cleanup has not recorded the terminal state

### Requirement: Evidence traversal is bounded and typed
GraphQL SHALL expose scoped task/tasks and taskResult/taskResults roots. Outcome roots SHALL select submitted outcomes with an optional acceptedOnly filter; that filter SHALL not create a separate visibility mode for every child resource. TaskParticipations, input presentations, typed answer children, and review history SHALL be nested connections with default 50/max 100 and stable identity tie-breakers. Separate accepted/audit roots for every persistence resource SHALL not exist. Result traversal SHALL exclude unsubmitted drafts even for a reader who also owns a live participation. Interactive pagination SHALL reflect current decisions, without claiming a multi-request snapshot.

#### Scenario: A result contains many spans
- **WHEN** an outcome contains more than one page of spans
- **THEN** every child remains reachable through its ordered paginated relationship

#### Scenario: A dual-role reader inspects task results
- **WHEN** a result reader also owns a live draft in that project
- **THEN** the result graph excludes that draft; it remains available only through the owned work bundle

#### Scenario: A released attempt is inspected
- **WHEN** a result reader traverses a task's terminal participation history after the worker returns work
- **THEN** the returned state and input presentation remain visible while draft answers stay hidden
