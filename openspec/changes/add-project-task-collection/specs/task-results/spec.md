## Purpose

Expose attributable accepted answers and audit evidence through scoped paginated reads and reproducible immutable asynchronous exports.

## ADDED Requirements

### Requirement: Result access is an explicit organization capability
Result and export operations SHALL require an active account, active owning organization, active membership, explicit organization/project scope, and `tasks.results.read`. Worker eligibility, ownership of one attempt, or another organization's permission SHALL not authorize result browsing. Reads SHALL return all effectively accepted question answers with exact project, form/schema version, task, revision, input, question, worker, and review provenance; they SHALL not select a canonical answer or synthesize consensus. Audit reads SHALL additionally expose submitted skips, pending/rejected outcomes, immutable review history, and expired/released/cancelled attempts with their offered questions and actual presentation. General results SHALL omit all unsubmitted draft payloads, including terminal drafts, account email/authentication secrets, storage credentials, and compensation fields. Result and export GraphQL responses, including access failures, SHALL inherit `Cache-Control: no-store` from the existing HTTP request-security boundary.

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
Result-scoped reads SHALL expose the immutable question key/prompt/family, referenced option keys/labels and annotation label keys/text, frozen input bindings, and exact bound dataset values needed to interpret eligible evidence. This authority SHALL require only the existing result-read checks, not additional `forms.read`, `datasets.read`, or `assets.read` grants. Bindings SHALL identify their input slot, requirement key/family/intended use, and bound field identity/key; value records SHALL identify their immutable revision/field and exact typed content. Reads SHALL identify optional absence explicitly. In complete default exports, a bound optional field on an exact revision with no matching value record SHALL denote absence; partial context filters SHALL not imply absence from an omitted record. Asset values SHALL expose immutable asset identity/hash/size/media metadata and permit separately authorized short-lived opaque source downloads through Tasks; exports SHALL not embed asset bytes, storage credentials, or expiring URLs. This access SHALL be confined to definitions and bound values referenced by eligible result evidence, with no general form/dataset/asset browsing or unbound-field traversal.

Result context SHALL include the complete published PresentationElement sequence pinned by each included attempt, retaining each element's original identity, form-version identity, kind, position, plain text, and question/requirement references. Combine that sequence with AttemptQuestions to identify offered questions and AttemptInputPresentations to recover actual input order for bound-value placements. Definitions referenced by these placements SHALL remain available as context even when a question was not offered on that attempt; this SHALL not expose that question's excluded response payloads or change answer selection. No copied presentation resources or additional per-attempt presentation snapshot SHALL be required.

Default exports without evidence-kind/ID filters SHALL include that referenced context as flat records: `presentation_element`, `question_definition`, `question_option`, `label`, `project_input_binding`, and `dataset_value`, deduplicated by kind/ID. Shared context SHALL retain its original immutable identity without copying product data into new persistence resources. Explicit evidence filters MAY select only part of that graph; callers SHALL be able to retrieve omitted context through the same scoped reads or context-kind exports without additional foundation capabilities. Every context record SHALL count toward the same combined 100,000-record selection cap and artifact byte limits as answer evidence, under the same snapshot guarantees; there SHALL be no separate context allowance.

#### Scenario: A result-only reader interprets selected evidence
- **WHEN** a member with `tasks.results.read` and no form/dataset/asset grants reads or exports choices, rankings, or labeled spans
- **THEN** they can resolve the original question, selected option labels, annotation label text, input bindings, and bound source content under result scope; unbound fields and unrelated definitions/assets remain denied

#### Scenario: A caller exports one evidence kind
- **WHEN** an authorized caller requests only task-input answers in a bounded ID range
- **THEN** the artifact contains only those records and their provenance references, and the caller can retrieve their immutable meaning through scoped context reads or separately filtered context exports

#### Scenario: Instructions give a prompt its meaning
- **WHEN** a worker's pinned form contains instructions, headings, section markers, bound-value placements, and question placements, and its attempt offers only some questions
- **THEN** result-only reads and default exports include the original element content, references, and sequence plus the offered-question set and actual input order, without substituting a later form version or exposing excluded answer payloads

### Requirement: Evidence traversal is bounded and typed
Tasks, attempts, offered questions, presentations, outcomes, typed answer children, reviews, and exports SHALL be exposed through explicit typed relationships and stable Relay keyset connections with default 50/max 100. Ordering SHALL use stable identity tie-breakers; authored/presentation order and review order SHALL remain meaningful. Direct scoped lookups SHALL resolve known evidence owners without searching all project records. Interactive result pagination SHALL reflect current effective decisions and SHALL not claim a multi-request snapshot; exports provide that guarantee.

#### Scenario: A result has many text spans
- **WHEN** a reader inspects an outcome with more than one page of child evidence
- **THEN** all children are reachable through bounded ordered connections without an unbounded expansion

#### Scenario: A terminal attempt has an unsubmitted draft
- **WHEN** a result reader inspects or exports audit evidence after an attempt expires, is released, or is cancelled
- **THEN** its terminal state, offered questions, presentation, and bound input context are available, but its unsubmitted draft outcomes and children are excluded

### Requirement: Export selection is a committed immutable snapshot
An export request SHALL choose accepted or audit mode and optionally an immutable inclusive task-ID range, an evidence kind, and an inclusive evidence-ID range within that kind. An evidence-ID range SHALL require an evidence kind; all supplied filters SHALL intersect. Callers SHALL be able to partition outcomes, typed child evidence, and review decisions within a single task using their existing immutable IDs and scoped evidence connections. Each request SHALL create an asynchronous export with visible queued, snapshotting, writing, ready, and failed states. The system SHALL check the requester's current capability and organization activity before materializing its first snapshot. It SHALL atomically pin committed evidence membership, the effective decision identities, and audit review history as of one snapshot, recording its time only when selection is sealed. Accepted mode SHALL select evidence supporting effectively accepted outcomes and their effective decisions at that snapshot; audit mode SHALL additionally include submitted nonaccepted outcomes, terminal attempts, and review history, excluding all unsubmitted draft payloads. Filters SHALL select records from that mode's eligible evidence without implicitly expanding related collections outside the filters. A bare timestamp cutoff SHALL not replace consistent committed membership. Retries after snapshot sealing SHALL retain the same selection even when later decisions or submissions occur. Separately requested partitions SHALL have independent snapshots and SHALL not claim a shared point in time.

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
Exports SHALL produce format-versioned JSONL with one bounded header and one line per selected evidence row ordered by kind then immutable ID. Core evidence kinds SHALL be `task`, `task_input`, `attempt`, `attempt_question`, `attempt_input_presentation`, `question_response`, `static_option_answer`, `task_input_answer`, `text_span`, `review_decision`, `presentation_element`, `question_definition`, `question_option`, `label`, `project_input_binding`, and `dataset_value`. Rows SHALL retain exact owner/provenance IDs and authored/presentation/review order fields as applicable; related collections SHALL be separate records rather than nested expansions. Shared evidence SHALL be deduplicated by kind/ID. Decimals SHALL retain exact precision and hashes SHALL use lowercase hexadecimal. Persistence of project/answer content SHALL remain relational; JSONL is only the output format. The 100,000-record selection cap SHALL count every serialized evidence row, including typed children, effective decisions, audit history, and all presentation/definition/binding/value context; only the single bounded header SHALL be excluded. Selection SHALL stop and roll back on the 100,001st eligible record before sealing any membership, counts, or snapshot time. The artifact SHALL produce at most 256 MiB or the lower configured asset maximum. Oversized output SHALL fail without a downloadable partial artifact. Callers SHALL be able to narrow both task and evidence ranges. Generation SHALL use bounded memory and temporary storage and publish one verified immutable organization asset only after the entire artifact succeeds.

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
