# task-results Specification

## Purpose

Expose attributable accepted answers and audit evidence through scoped paginated reads and reproducible immutable asynchronous exports.

## Requirements

### Requirement: Result access is an explicit organization capability
Result and export operations SHALL require an active account, active owning organization, active membership, explicit organization/project scope, and `tasks.results.read`. Worker eligibility, ownership of one attempt, or another organization's permission SHALL not authorize result browsing. Reads SHALL return all effectively accepted question answers with exact project, form/schema version, task, revision, input, question, worker, and review provenance; they SHALL not select a canonical answer or synthesize consensus. Audit reads SHALL additionally expose submitted skips, pending/rejected outcomes, immutable review history, and expired/released/cancelled attempts with their actual presentation. General results SHALL omit all unsubmitted draft payloads, including terminal drafts, account email/authentication secrets, storage credentials, and compensation fields. Result and export GraphQL responses, including access failures, SHALL inherit `Cache-Control: no-store` from the existing HTTP request-security boundary.

#### Scenario: Several accepted answers disagree
- **WHEN** a result reader inspects a question with different accepted answers
- **THEN** every accepted answer is returned with its own evidence and no answer is silently designated truth

#### Scenario: A worker requests the organization's results
- **WHEN** an external worker possessing an attempt ID queries result collections
- **THEN** access fails without disclosing other workers or results

#### Scenario: Result operations pass through the HTTP boundary
- **WHEN** a caller requests result evidence, export status, or export download issuance through GraphQL
- **THEN** successful responses and authorization failures include `Cache-Control: no-store`

### Requirement: Result context makes answers interpretable
Collection context SHALL reuse canonical Forms, Datasets, Assets, and ProjectInputBinding resources without mirrored definitions or persisted copies. Published definitions SHALL be reached through scoped tasks, submitted outcomes, or owned work bundles; standalone collection-definition roots SHALL not be exposed. Each traversal SHALL recheck current worker or result authority and exact issued-input/bound-field membership. Caller-provided context alone SHALL confer no authority. Assets SHALL hide storage keys and operation claims through native field policies.

Result-only readers SHALL resolve question keys/prompts/families/renderers, complete typed constraints, selected options and labels, pinned presentation elements, input requirements, bound field identities, and exact source values without additional forms/datasets/assets grants. The at-most-one text, integer, decimal, selection, and annotation constraint objects SHALL retain original IDs and fields. Absent constraints SHALL remain distinguishable from present null bounds, and decimals SHALL remain exact. The export header SHALL include published question definitions with their fixed typed constraints and options, plus shared labels, presentation, and bindings. Interactive options and labels SHALL remain typed connections.

The complete pinned presentation sequence and per-attempt input order SHALL explain the whole form. Nonempty exports SHALL include shared pinned form context once in the header. Each result SHALL embed its actual input order, exact revision identities, and bound typed values. For an exact input revision and binding, absence of a value in that input SHALL denote optional absence. Asset context SHALL include immutable identity/hash/size/media facts, never file bytes, credentials, or expiring URLs. New source downloads SHALL be separately authorized and short-lived. No unbound-field or general organization browsing SHALL be authorized.

#### Scenario: A result-only reader interprets an answer
- **WHEN** a member with tasks.results.read reads choices, rankings, or labeled spans
- **THEN** its question, typed constraints, labels, exact inputs, and bound sources are available through scoped context while unrelated records remain denied

#### Scenario: A constraint is absent
- **WHEN** an integer question without a constraint record appears alongside a bounded Likert question
- **THEN** reads and exports retain their distinct renderers, bounds, and explicit constraint absence

#### Scenario: Instructions explain a response
- **WHEN** a pinned form includes headings, instructions, and bound-value placements
- **THEN** results preserve the original sequence and actual input order without substituting a newer form version

### Requirement: Evidence traversal is bounded and typed
GraphQL SHALL expose scoped task/tasks and taskResult/taskResults roots. Outcome roots SHALL select submitted outcomes with an optional acceptedOnly filter; that filter SHALL not create a separate visibility mode for every child resource. Attempts, input presentations, typed answer children, and review history SHALL be nested connections with default 50/max 100 and stable identity tie-breakers. Separate accepted/audit roots for every persistence resource SHALL not exist. Result traversal SHALL exclude unsubmitted drafts even for a reader who also owns a live attempt. Interactive pagination SHALL reflect current decisions, without claiming a multi-request snapshot.

#### Scenario: A result contains many spans
- **WHEN** an outcome contains more than one page of spans
- **THEN** every child remains reachable through its ordered paginated relationship

#### Scenario: A dual-role reader inspects task results
- **WHEN** a result reader also owns a live draft in that project
- **THEN** the result graph excludes that draft; it remains available only through the owned work bundle

#### Scenario: A released attempt is inspected
- **WHEN** a result reader traverses a task's terminal attempt history
- **THEN** the terminal state and input presentation remain visible while draft answers stay hidden

### Requirement: Export selection is a committed immutable snapshot
Exports SHALL select complete project results in accepted or audit mode, without task-ID ranges, evidence-kind filters, or evidence-ID ranges. New requests SHALL require an activated project. Selection SHALL recheck the requester's current results capability and organization activity, then atomically seal one ExportSelection per selected submitted QuestionResponse in a repeatable-read transaction. Each membership SHALL pin the outcome and its effective decision ID, with scoped foreign keys and membership uniqueness. The system SHALL derive immutable task/input/attempt metadata, typed children, form context, bindings, and source values from those selected outcomes rather than persist per-kind membership rows.

Accepted exports SHALL include effectively accepted outcomes and their pinned effective decisions. Audit exports SHALL include all submitted outcomes and decision history up to each pinned effective decision's number. Neither SHALL include unsubmitted outcomes or standalone attempts without a selected submission. Empty snapshots SHALL have no context records. Snapshot time and the exact selected-result count SHALL be sealed with membership; a timestamp cutoff SHALL not substitute for transaction-consistent membership. Later submissions or corrections SHALL never change a sealed retry. JSON object keys, including nested constraint keys, and nested collection order SHALL be deterministic across VM restarts. The feature is unreleased; no historical response IDs, migrated membership variants, or old export-byte compatibility SHALL be required.

#### Scenario: A correction arrives after sealing
- **WHEN** an accepted answer is later rejected
- **THEN** an existing export retains its selected answer and original decision, while a new export can reflect the correction

#### Scenario: A submission commits after selection
- **WHEN** a submission starts before snapshotting but commits afterward
- **THEN** the sealed snapshot excludes it consistently

#### Scenario: Audit history changes after sealing
- **WHEN** a later correction appends another review decision
- **THEN** a sealed audit retry still ends at the pinned decision number

#### Scenario: An empty export gains work later
- **WHEN** later work is submitted after a header-only snapshot seals
- **THEN** retries remain header-only

### Requirement: Exports stream and publish atomically
Exports SHALL produce format-versioned JSONL with one metadata header followed by one result record per selected submitted QuestionResponse, ordered by response ID. record_count SHALL count result records only, excluding the header, and serialize as an exact nonnegative decimal string. A nonempty header SHALL contain shared pinned presentation elements, questions with typed constraints and options, labels, and project bindings with requirement/field definitions. An empty snapshot SHALL contain only the metadata header. Each result SHALL embed immutable task and attempt metadata, submitted scalar/skip content, its pinned effective decision ID, actual input presentation with exact revision identities and bound source values, typed answer children, and selected review history. No fifteen-kind persistence graph, per-kind counting, or consumer-side reconstruction of those owners SHALL be required. Decimals SHALL retain exact precision and hashes SHALL use lowercase hexadecimal. Source values SHALL be restricted to fields bound to the input's slot; optional absence SHALL remain distinguishable. Shared input context may repeat across results. Persistence of project/answer content SHALL remain relational; JSONL is only the output format. All nested collections, including questions, options, inputs, values, answer children, and review history, SHALL stream in bounded pages while Jason encodes their scalar/object values. Source values and typed children SHALL load in bounded batches across input presentations, retaining per-slot binding filters and the published limit of 64 single-value requirements per slot. This change SHALL impose no export record-count or output-byte ceiling. Existing Assets/provider publication constraints SHALL still apply, with the configured asset byte cap checked during temporary-file generation before each write; a publication failure SHALL expose no downloadable partial artifact. Temporary output SHALL be cleaned up and publication SHALL expose one verified immutable organization asset only after the entire artifact succeeds.

#### Scenario: Asset publication fails
- **WHEN** export publication fails under the configured Assets/provider contract
- **THEN** it returns a sanitized failure with no ready download or partially published artifact

#### Scenario: Backend staging writes exceed their operation deadline
- **WHEN** streaming generated bytes exceeds the configured Assets publication deadline
- **THEN** the adapter fails in finite time without partial or late staging commits, the export records a retryable failure while retaining its sealed snapshot and pending-asset identity, temporary output is cleaned up, and no ready download is exposed

#### Scenario: An export contains many child records
- **WHEN** selected outcomes include extensive typed children and review history
- **THEN** generation streams every selected record from the sealed snapshot without truncating the evidence or imposing an export-specific count limit

#### Scenario: The output contains a precise decimal
- **WHEN** an exported answer is a decimal
- **THEN** JSONL represents it as an exact string rather than an imprecise binary floating-point number

### Requirement: Export retries and downloads preserve authority
Export requests SHALL use a native Ash create action and domain interface, with GraphQL input and result/errors output. Ash SHALL attribute the requester from the actor and persist the export and its job in the same transaction. Identical retries SHALL return the existing export without enqueueing another job. Export requests SHALL require caller-supplied UUID request keys. Invalid UUID input SHALL fail validation before persistence or job enqueue, without creating an export. Repeated requests with the same organization/project/requesting-actor key and identical mode SHALL resolve to one export; conflicting arguments SHALL fail, including a changed mode. Before any snapshot is sealed, failed selection transactions SHALL remain retryable after rechecking current requester authority. Once sealed, job retries SHALL reuse that membership and converge on one ready immutable artifact, never regenerate a newer snapshot under that identity. Reads and download issuance SHALL recheck current results capability and organization activity. Downloads SHALL use existing short-lived opaque-asset access without disclosing storage credentials. Storage incapable of backend staging writes or compliant access SHALL fail explicitly with no ready download; the in-memory adapter SHALL not be represented as a reachable HTTP service. Failure SHALL expose a sanitized reason without draft values, credentials, or partially published artifacts.

#### Scenario: A project edit races snapshot selection
- **WHEN** a concurrent project edit causes snapshot selection to fail before sealing
- **THEN** the export retains no partial snapshot, and a later authorized job attempt can select and publish its first snapshot under the same export identity

#### Scenario: A job retries after publishing bytes
- **WHEN** the export worker crashes after sealing content but before recording completion
- **THEN** its retry verifies/reuses the same snapshot's canonical content and completes one export

#### Scenario: An unpublished export upload fails or expires
- **WHEN** a sealed export retries after its unpublished asset fails or reaches its staging deadline
- **THEN** it replaces that asset under the export lock while retaining the export identity, sealed membership, snapshot timestamp, record count, and content facts; superseded assets retain export ownership, and later submissions do not enter the export
- **AND** unexpired pending uploads and already published assets continue to be reused

#### Scenario: The requester's permission is revoked
- **WHEN** a ready export's requester or another reader lacks the current results capability
- **THEN** new export inspection/download access is denied even though the artifact already exists

### Requirement: Export processing is independent of media interpretation
Export snapshotting, serialization, byte publication, and access authorization for supported collection outcomes SHALL operate without image decoding, verified image dimensions, or an image-serving component. Publication SHALL use the existing opaque asset integrity contract and a storage adapter supporting the required operations. An unavailable adapter SHALL fail explicitly without a partial download, while scoped result inspection and export status remain accessible. Only actual file transfer SHALL require reachable compliant endpoints; the system SHALL not treat an in-memory contract descriptor as a reachable service.

#### Scenario: Ordinary answers are exported without media support
- **WHEN** an authorized caller exports supported scalar, choice, ranking, or text-span outcomes with compliant storage operations but no image capability
- **THEN** the system creates the immutable artifact without calling a media service or requiring verified image facts
