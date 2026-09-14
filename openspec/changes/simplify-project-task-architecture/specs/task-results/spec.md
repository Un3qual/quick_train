## MODIFIED Requirements

### Requirement: Result context makes answers interpretable
Collection context SHALL reuse the canonical Forms, Datasets, Assets, and ProjectInputBinding resources, relationships, and GraphQL types, without mirrored resource definitions or persisted copies. Collection entry points SHALL remain explicitly scoped in Tasks. Canonical resources SHALL integrate shared Authorization checks for collection reads alongside their ordinary domain policies, and a shared native Ash fragment SHALL provide scoped definition reads. Every collection context traversal SHALL recheck live worker or result authority, including exact issued input and bound field membership; caller-supplied traversal context alone SHALL confer no authority. Asset metadata reads SHALL use native field policies to hide private storage keys and operation claims.

Result-scoped reads SHALL expose the immutable question key/prompt/family/renderer and complete published typed constraints, referenced option keys/labels and annotation label keys/text, frozen input bindings, and exact bound dataset values needed to interpret eligible evidence. This authority SHALL require only the existing result-read checks, not additional `forms.read`, `datasets.read`, or `assets.read` grants. Bindings SHALL identify their input slot, requirement key/family/intended use, and bound field identity/key; value records SHALL identify their immutable revision/field and exact typed content. Reads SHALL identify optional absence explicitly. In complete default exports, a bound optional field on an exact revision with no matching value record SHALL denote absence; partial context filters SHALL not imply absence from an omitted record. Asset values SHALL expose immutable asset identity/hash/size/media metadata and permit separately authorized short-lived opaque source downloads through Tasks; exports SHALL not embed asset bytes, storage credentials, or expiring URLs. This access SHALL be confined to definitions and bound values referenced by eligible result evidence, with no general form/dataset/asset browsing or unbound-field traversal.

Question context SHALL preserve input-slot/source-requirement references and the original identities and all published fields of its at-most-one text, integer, decimal, selection, and annotation constraint records, including minimum/maximum bounds and annotation source/label-set references and source convention. An absent constraint record SHALL remain distinguishable from a present record with null bounds; the published Forms defaults SHALL remain unchanged. Each `question_definition` export record SHALL include this renderer and fixed set of typed constraint fields/objects in the same row. Optional absence and exact decimal bounds SHALL be preserved. Options and labels SHALL remain separately paginated/read and separately exported records; no new constraint export kinds or copied persistence resources SHALL be introduced.

Result context SHALL include the complete published PresentationElement sequence pinned by each included attempt, retaining each element's original identity, form-version identity, kind, position, plain text, and question/requirement references. Combine that sequence with AttemptQuestions to identify offered questions and AttemptInputPresentations to recover actual input order for bound-value placements. Definitions referenced by these placements SHALL remain available as context even when a question was not offered on that attempt; this SHALL not expose that question's excluded response payloads or change answer selection. No copied presentation resources or additional per-attempt presentation snapshot SHALL be required.

Default exports without evidence-kind/ID filters SHALL include that referenced context as flat records: `presentation_element`, `question_definition`, `question_option`, `label`, `project_input_binding`, and `dataset_value`, deduplicated by kind/ID. Shared context SHALL retain its original immutable identity without copying product data into new persistence resources. Explicit evidence filters MAY select only part of that graph; callers SHALL be able to retrieve omitted context through the same scoped reads or context-kind exports without additional foundation capabilities. Context records SHALL use the same snapshot guarantees and exact record accounting as answer evidence; this change SHALL impose no context or total-record allowance.

#### Scenario: A result-only reader interprets selected evidence
- **WHEN** a member with `tasks.results.read` and no form/dataset/asset grants reads or exports choices, rankings, or labeled spans
- **THEN** they can resolve the original question, selected option labels, annotation label text, input bindings, and bound source content under result scope; unbound fields and unrelated definitions/assets remain denied

#### Scenario: A result-only reader reconstructs a typed question contract
- **WHEN** a result-only reader reads or exports a Likert integer question bounded 1–5 alongside an ordinary integer-input question with no constraint record
- **THEN** their question definitions retain distinct renderers, the Likert constraint identity and bounds, and explicit absence of the ordinary integer constraint with the published default semantics, without requiring Forms access

#### Scenario: A caller exports one evidence kind
- **WHEN** an authorized caller requests only task-input answers in a bounded ID range
- **THEN** the artifact contains only those records and their provenance references, and the caller can retrieve their immutable meaning through scoped context reads or separately filtered context exports

#### Scenario: Instructions give a prompt its meaning
- **WHEN** a worker's pinned form contains instructions, headings, section markers, bound-value placements, and question placements, and its attempt offers only some questions
- **THEN** result-only reads and default exports include the original element content, references, and sequence plus the offered-question set and actual input order, without substituting a later form version or exposing excluded answer payloads

### Requirement: Export selection is a committed immutable snapshot
Ash create validations SHALL enforce each selection kind's required, optional, and forbidden owner fields for ordinary and bulk writes. These rules SHALL live in Elixir rather than a PostgreSQL business-rule check. The database SHALL retain scoped foreign keys, membership uniqueness, and positive record counts.

A new export request SHALL require an activated project in active, paused, completed, or archived state, preserving its frozen source contract. Identical existing request-key retries SHALL still recheck current authority. An export request SHALL choose accepted or audit mode and optionally an immutable inclusive task-ID range, an evidence kind, and an inclusive evidence-ID range within that kind. An evidence-ID range SHALL require an evidence kind; all supplied filters SHALL intersect. Callers SHALL be able to partition outcomes, typed child evidence, and review decisions within a single task using their existing immutable IDs and scoped evidence connections. Each request SHALL create an asynchronous export with visible queued, snapshotting, writing, ready, and failed states. The system SHALL check the requester's current capability and organization activity before materializing its first snapshot. It SHALL atomically pin committed evidence membership, the effective decision identities, and audit review history as of one snapshot, recording its time only when selection is sealed. Accepted mode SHALL select evidence supporting effectively accepted outcomes and their effective decisions at that snapshot; audit mode SHALL additionally include submitted nonaccepted outcomes, terminal attempts, and review history, excluding all unsubmitted draft payloads. Filters SHALL select records from that mode's eligible evidence without implicitly expanding related collections outside the filters. Immutable presentation/question/option/label membership SHALL be determined by the pinned published form version, immutable export filters, and form-context eligibility sealed in the same snapshot. The system SHALL not persist a separate membership row per immutable Forms record. Exports with no eligible attempt at sealing SHALL include no Forms context. Changing evidence and source-value membership SHALL remain explicitly pinned, with exact record counts across both kinds of context. A bare timestamp cutoff SHALL not replace consistent committed membership. JSON object keys, including nested constraint keys, SHALL have deterministic lexical order so retries across runtime restarts reproduce the same bytes. Retries after snapshot sealing SHALL retain the same selection even when later decisions or submissions occur. Separately requested partitions SHALL have independent snapshots and SHALL not claim a shared point in time.

#### Scenario: A draft project remains editable after an export request
- **WHEN** a result reader requests a new export for a project that has never been activated
- **THEN** the request fails before export or job persistence and does not prevent later draft source-contract changes
- **AND** new exports remain available for active, paused, completed, and archived projects, whose source contracts are frozen

#### Scenario: A decision is corrected while export runs
- **WHEN** an answer accepted in the sealed snapshot is later rejected
- **THEN** that export retains its selected answer/decision provenance while a newly requested export can reflect the correction

#### Scenario: A transaction commits after snapshot selection
- **WHEN** a submission starts before export snapshotting but commits after its snapshot
- **THEN** it is excluded consistently rather than included because its timestamp is earlier

#### Scenario: A caller selects part of one task
- **WHEN** an authorized caller wants only a range of child records or review decisions from a task
- **THEN** it can select that evidence kind and ID range without exporting the task's entire history

#### Scenario: A sealed export predates architecture consolidation
- **WHEN** existing response ownership and immutable form memberships are migrated
- **THEN** its selected records, historical response identifiers, counts, and already-published artifact bytes remain unchanged; unpublished retries retain their snapshot and regenerate with deterministic JSON key ordering

#### Scenario: An empty export gains eligible work later
- **WHEN** an export seals without an eligible attempt and work is subsequently submitted
- **THEN** retrying that export still includes no form context or newly eligible evidence
