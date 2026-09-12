## Purpose

Expose attributable accepted answers and audit evidence through scoped paginated reads and reproducible immutable asynchronous exports.

## ADDED Requirements

### Requirement: Result access is an explicit organization capability
Result and export operations SHALL require an active account, active owning organization, active membership, explicit organization/project scope, and `tasks.results.read`. Worker eligibility, ownership of one attempt, or another organization's permission SHALL not authorize result browsing. Reads SHALL return all effectively accepted question answers with exact project, form/schema version, task, revision, input, question, worker, and review provenance; they SHALL not select a canonical answer or synthesize consensus. Audit reads SHALL additionally expose submitted skips, pending/rejected outcomes, immutable review history, and expired/released/cancelled attempts with their offered questions and actual presentation. General results SHALL omit mutable live drafts, account email/authentication secrets, storage credentials, and compensation fields. Result and export GraphQL responses, including access failures, SHALL inherit `Cache-Control: no-store` from the existing HTTP request-security boundary.

#### Scenario: Several accepted answers disagree
- **WHEN** a result reader inspects a question with different accepted answers
- **THEN** every accepted answer is returned with its own evidence and no answer is silently designated truth

#### Scenario: A worker requests the organization's results
- **WHEN** an external worker possessing an attempt ID queries result collections
- **THEN** access fails without disclosing other workers or results

#### Scenario: Result operations pass through the HTTP boundary
- **WHEN** a caller requests result evidence, export status, or export download issuance through GraphQL
- **THEN** successful responses and authorization failures include `Cache-Control: no-store`

### Requirement: Evidence traversal is bounded and typed
Tasks, attempts, offered questions, presentations, outcomes, typed answer children, reviews, and exports SHALL be exposed through explicit typed relationships and stable Relay keyset connections with default 50/max 100. Ordering SHALL use stable identity tie-breakers; authored/presentation order and review order SHALL remain meaningful. Direct scoped lookups SHALL resolve known evidence owners without searching all project records. Interactive result pagination SHALL reflect current effective decisions and SHALL not claim a multi-request snapshot; exports provide that guarantee.

#### Scenario: A result has many text spans
- **WHEN** a reader inspects an outcome with more than one page of child evidence
- **THEN** all children are reachable through bounded ordered connections without an unbounded expansion

### Requirement: Export selection is a committed immutable snapshot
An export request SHALL choose accepted or audit mode and optionally an immutable inclusive task-ID range, an evidence kind, and an inclusive evidence-ID range within that kind. An evidence-ID range SHALL require an evidence kind; all supplied filters SHALL intersect. Callers SHALL be able to partition outcomes, typed child evidence, and review decisions within a single task using their existing immutable IDs and scoped evidence connections. Each request SHALL create an asynchronous export with visible queued, snapshotting, writing, ready, and failed states. The system SHALL check the requester's current capability and organization activity before materializing its first snapshot. It SHALL atomically pin committed evidence membership, the effective decision identities, and audit review history as of one snapshot, recording its time only when selection is sealed. Accepted mode SHALL select evidence supporting effectively accepted outcomes and their effective decisions at that snapshot; audit mode SHALL additionally include submitted nonaccepted outcomes, terminal attempts, and review history, excluding mutable live drafts. Filters SHALL select records from that mode's eligible evidence without implicitly expanding related collections outside the filters. A bare timestamp cutoff SHALL not replace consistent committed membership. Retries after snapshot sealing SHALL retain the same selection even when later decisions or submissions occur. Separately requested partitions SHALL have independent snapshots and SHALL not claim a shared point in time.

#### Scenario: A decision is corrected while export runs
- **WHEN** an answer accepted in the sealed snapshot is later rejected
- **THEN** that export retains its selected answer/decision provenance while a newly requested export can reflect the correction

#### Scenario: A transaction commits after snapshot selection
- **WHEN** a submission starts before export snapshotting but commits after its snapshot
- **THEN** it is excluded consistently rather than included because its timestamp is earlier

#### Scenario: One task exceeds the export selection cap
- **WHEN** one task has more than 100,000 eligible evidence records, including extensive review history
- **THEN** the caller can request bounded partitions by evidence kind and ID range inside that task, including review-decision and child-record ranges, without fetching its entire history in every partition

### Requirement: Export bytes are bounded and published atomically
Exports SHALL produce format-versioned JSONL with one bounded header and one line per selected evidence row ordered by kind then immutable ID. Core evidence kinds SHALL be `task`, `task_input`, `attempt`, `attempt_question`, `attempt_input_presentation`, `question_response`, `static_option_answer`, `task_input_answer`, `text_span`, and `review_decision`. Rows SHALL retain exact owner/provenance IDs and authored/presentation/review order fields as applicable; related collections SHALL be separate records rather than nested expansions. Shared evidence SHALL be deduplicated by kind/ID. Decimals SHALL retain exact precision and hashes SHALL use lowercase hexadecimal. Persistence of project/answer content SHALL remain relational; JSONL is only the output format. The 100,000-record selection cap SHALL count every serialized evidence row, including typed children, effective decisions, and audit history; only the single bounded header SHALL be excluded. Selection SHALL stop and roll back on the 100,001st eligible record before sealing any membership, counts, or snapshot time. The artifact SHALL produce at most 256 MiB or the lower configured asset maximum. Oversized output SHALL fail without a downloadable partial artifact. Callers SHALL be able to narrow both task and evidence ranges. Generation SHALL use bounded memory and temporary storage and publish one verified immutable organization asset only after the entire artifact succeeds.

#### Scenario: An export exceeds its cap
- **WHEN** the selected evidence or generated bytes exceed the documented bound
- **THEN** it fails with a sanitized limit error and no ready download, leaving the caller able to request a narrower range

#### Scenario: Child evidence exceeds the cap before its parents do
- **WHEN** fewer than 100,000 outcomes expand to more than 100,000 total eligible records through typed children and review decisions
- **THEN** selection stops at the limit and rolls back without a partial snapshot; individual child/history ranges remain available for smaller requests

#### Scenario: The output contains a precise decimal
- **WHEN** an exported answer is a decimal
- **THEN** JSONL represents it as an exact string rather than an imprecise binary floating-point number

### Requirement: Export retries and downloads preserve authority
Repeated requests with the same organization/project/requesting-actor key and identical mode and all selection filters SHALL resolve to one export; conflicting arguments SHALL fail, including a changed evidence kind or ID range. Job retries SHALL reuse its sealed membership and converge on one ready immutable artifact, never regenerate a newer snapshot under that identity. Reads and download issuance SHALL recheck current results capability and organization activity. Downloads SHALL use existing short-lived opaque-asset access without disclosing storage credentials. Storage incapable of backend staging writes or compliant access SHALL fail explicitly with no ready download; the in-memory adapter SHALL not be represented as a reachable HTTP service. Failure SHALL expose a sanitized reason without draft values, credentials, or partially published artifacts.

#### Scenario: A job retries after publishing bytes
- **WHEN** the export worker crashes after sealing content but before recording completion
- **THEN** its retry verifies/reuses the same snapshot's canonical content and completes one export

#### Scenario: The requester's permission is revoked
- **WHEN** a ready export's requester or another reader lacks the current results capability
- **THEN** new export inspection/download access is denied even though the artifact already exists

### Requirement: Export processing is independent of media interpretation
Export snapshotting, serialization, byte publication, and access authorization for supported collection outcomes SHALL operate without image decoding, verified image dimensions, or an image-serving component. Publication SHALL use the existing opaque asset integrity contract and a storage adapter supporting the required operations. An unavailable adapter SHALL fail explicitly without a partial download, while scoped result inspection and export status remain accessible. Only actual file transfer SHALL require reachable compliant endpoints; the system SHALL not treat an in-memory contract descriptor as a reachable service.

#### Scenario: Ordinary answers are exported without media support
- **WHEN** an authorized caller exports supported scalar, choice, ranking, or text-span outcomes with compliant storage operations but no image capability
- **THEN** the system creates the immutable artifact without calling a media service or requiring verified image facts
