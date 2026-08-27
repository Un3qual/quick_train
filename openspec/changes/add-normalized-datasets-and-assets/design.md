## Context

See `proposal.md` for motivation and the three delta specs for behavioral requirements.

QuickTrain currently contains backend-only account, organization, authorization, enterprise identity, and GraphQL foundations. It has no product datasets, forms, projects, tasks, finance, or reputation resources. The current session resource can hold a hashed token, but the GraphQL pipeline does not yet resolve an authenticated actor and several foundation domains expose policy-disabled GraphQL operations. Product data must not inherit that posture.

This change is the first of five approved product changes:

1. `add-normalized-datasets-and-assets`
2. `add-versioned-forms`
3. `add-project-task-collection`
4. `add-marketplace-finance`
5. `add-worker-reputation`

The implementation scope of this change is only the first item. The final appendix is a durable record of approved cross-change decisions, not an expansion of this change's requirements or tasks.

## Goals / Non-Goals

**Goals:**

- Add organization-owned asset and dataset domains using Ash resources and AshPostgres.
- Normalize dataset content into schemas, record types, field definitions, item revisions, records, value occurrences, and typed value tables.
- Keep source content immutable and historically unambiguous.
- Support idempotent programmatic import batches without persisting opaque item payloads.
- Establish an additive path to repeated and nested record values without implementing arbitrary nested input now.
- Establish authenticated, fail-closed GraphQL actions before exposing product content.
- Use product-specific durable jobs for asset verification and import processing.

**Non-Goals:**

- Implement Forms, Projects, Tasks, responses, review, exports, Finance, or Reputation.
- Choose a production object-storage vendor.
- Add frontend code or external form integration.
- Store dataset content or import row payloads in JSONB.
- Create customer-specific PostgreSQL tables.
- Implement nested record values, item graphs, or arbitrary recursive input in this change.
- Implement audio/video annotation ranges or any task answer representation.

## Decisions

### 1. Add `QuickTrain.Assets` and `QuickTrain.Datasets` as separate Ash domains

`QuickTrain.Assets` owns immutable binary-content identity and authorized storage access. `QuickTrain.Datasets` owns customer schemas and normalized logical content. Datasets depend on Assets for asset-valued fields; Assets do not depend on Datasets.

The top-level `QuickTrain` boundary exports both domains and the asset storage behavior. Product resources use `AshGraphql.Resource`, and each domain uses `AshGraphql.Domain` with authorization enabled.

Alternatives rejected:

- One generic content domain would mix binary storage lifecycle with dataset schema and revision lifecycle.
- Placing assets inside Datasets would create an unnatural dependency when later raster-mask answers also need assets.
- A generic CRUD/service layer would obscure the product actions and authorization boundary.

### 2. Use immutable, content-addressed asset metadata with a provider-neutral adapter

`Asset` contains organization ownership, lifecycle state, SHA-256 content hash, byte size, media type, optional image width and height, an internal storage key, and timestamps. Ready assets are immutable. The same ready content may be reused within an organization by an identity on organization and content hash; cross-organization content does not share authorization even if bytes match.

`QuickTrain.Assets.Storage` is a narrow behavior for registration/upload access, verification, and short-lived read access. Development and tests use a deterministic filesystem/test adapter. Production configuration must select an adapter; this change does not choose S3 or another vendor.

Storage credentials and persistent object locations are never GraphQL fields. GraphQL returns only short-lived adapter-produced access descriptors after an Ash authorization action succeeds.

Alternatives rejected:

- Storing bytes in PostgreSQL would inflate backups and couple large-object delivery to the transactional database.
- Storing public URLs would bypass authorization and make asset relocation unsafe.
- Mutable object keys would invalidate spatial answers and historical item revisions later.

### 3. Model dataset schemas explicitly and publish immutable versions

Core resources:

```text
Dataset
└── DatasetSchemaVersion
    └── DatasetRecordType
        └── DatasetFieldDefinition
```

`Dataset` is a stable organization-owned container. A schema version begins as draft and becomes immutable when published. A version has one root record type in the first release. Field definitions have a stable key, display name, value family, required flag, and cardinality. Field keys are unique within a record type.

Initial value families are text, integer, decimal, boolean, UTC date-time, and asset. The first release accepts single-valued flat fields. Cardinality and occurrence ordinals are persisted now so repeated scalar values can be enabled without changing existing tables.

Alternatives rejected:

- Inferring a schema independently for every row makes validation and reusable form bindings unreliable.
- PostgreSQL enums for customer field names or customer-specific tables would require migrations for customer data.
- An untyped field catalog would move type failures from import time to task execution.

### 4. Give every item a stable identity and immutable revisions

```text
DatasetItem
└── DatasetItemRevision
    └── root DatasetRecord
        └── DatasetValue
            └── exactly one typed value child
```

`DatasetItem` is identified by a UUID and, when supplied, a customer external key unique within its dataset. `DatasetItemRevision` pins a published schema version, an immutable root record, a monotonically increasing revision number, and a content fingerprint.

Corrections create new revisions. Existing projects will later pin exact item revisions, so source text, images, boxes, masks, polygons, and spans cannot change underneath historical responses.

Revision creation locks the stable item row before comparing the latest fingerprint and assigning the next revision number. Database identities backstop external-key and revision-number uniqueness.

### 5. Use a typed record envelope rather than JSONB or a generic tree

`DatasetRecord` is an instance of a `DatasetRecordType`. Even a flat first-release item owns a root record. `DatasetValue` identifies one field occurrence with a field definition and ordinal. Typed one-to-one resources contain the value:

- `DatasetTextValue`
- `DatasetIntegerValue`
- `DatasetDecimalValue`
- `DatasetBooleanValue`
- `DatasetDateTimeValue`
- `DatasetAssetValue`

The root/value split is deliberate. Repeated values later require only allowing additional ordinals. Nested records later add a record-valued typed child pointing to another `DatasetRecord`; existing root, occurrence, and scalar rows remain unchanged.

Exactly one typed child must exist and match the field definition. Ash creation actions build the record graph transactionally. Because an ordinary PostgreSQL check constraint cannot count subtype rows, a deferred constraint trigger is an approved narrow database-boundary exception to reject missing, duplicate, or mismatched typed children at commit. The trigger is generated through the AshPostgres migration and covered by integration tests; application code does not use direct Ecto writes.

Alternatives rejected:

- Nullable scalar columns directly on each item make repeated and nested fields awkward.
- JSONB preserves import shape but loses relational typing, foreign keys, and efficient value-level validation.
- A fully generic self-referential EAV tree is flexible but weakens understandable type and ownership invariants.
- Type-specific tables without a stable value occurrence make generic form bindings and future record values harder to reference.

### 6. Process programmatic imports as normalized rows without staging opaque payloads

Core resources:

```text
DatasetImport
└── DatasetImportRow
```

An authorized manager opens an import against one dataset and published schema version, submits normalized rows in bounded GraphQL batches, and finalizes the import. Each row is processed into the canonical record/value resources immediately or by a product-specific durable job. The row record stores source position, external key, request fingerprint, outcome, target item/revision, and sanitized errors; it does not retain an opaque content payload.

Batch idempotency uses organization, dataset, caller-supplied idempotency key, and request fingerprint. A matching retry returns the existing batch. A changed request under the same key fails.

Rows commit independently so a large batch can finish partially. The batch state and counts derive from row outcomes. Retrying an interrupted batch skips terminal rows and processes unfinished rows. Rows targeting the same stable item serialize on its row lock.

Source-file format adapters are later additions. A future CSV or archive import can register its source file as an Asset and emit the same normalized row actions; it does not require a second dataset persistence model.

### 7. Make authorization actor-aware and fail closed before exposing product data

The API pipeline resolves an active account session from a bearer token, loads the global `User`, and sets it as the Absinthe and Ash actor. Product actions require:

1. an active authenticated user;
2. an active membership in the target organization; and
3. the relevant explicit capability.

Initial capability keys are `assets.manage`, `datasets.manage`, `datasets.import`, and read-only equivalents where separate read delegation is useful. Resource ownership is derived from relationships, not a trusted organization header. Internal relationship loads can bypass authorization only after the public action has proven scope and only through private actions.

The implementation must also close any supporting foundation GraphQL route that would otherwise expose the new product relationships through policy-disabled reads. `/healthz` and the authentication handshake remain the only unauthenticated surfaces.

### 8. Expose deliberate GraphQL lifecycle actions

Public actions cover:

- creating and reading datasets;
- drafting and publishing schema versions;
- defining root record types and fields while the version is draft;
- registering, finalizing, and obtaining authorized access to assets;
- opening, appending normalized rows to, finalizing, and inspecting imports; and
- paginated typed reads of items and revisions.

There are no public generic update/delete actions for published schema versions, ready asset content, item revisions, records, or typed values. GraphQL errors use stable codes such as `forbidden`, `invalid_schema`, `invalid_value`, `asset_not_ready`, `idempotency_conflict`, and `import_not_open`.

### 9. Use Ash transactions and row locks for related-data correctness

Publishing a schema locks the draft version and validates its complete field graph before the state transition. Creating a revision locks the stable item before comparing the latest content fingerprint and assigning the revision number. Every typed value validates its field and asset relationships inside the same transaction that creates the revision.

Ash actions, `Ash.DataLayer.transaction/5`, query locks, atomic changes, and `get_and_lock_for_update` are the default. `FOR UPDATE SKIP LOCKED` is reserved for later task allocation; imports targeting a known item use ordinary row locks. Direct SQL is limited to generated constraints/triggers that AshPostgres cannot express declaratively.

### 10. Reintroduce durable jobs only for product-specific asynchronous work

Oban is added at the stable GA version selected during implementation and pinned exactly with the rest of the dependency set. Initial workers are responsibility-named, for example `QuickTrain.Assets.VerifyWorker` and `QuickTrain.Datasets.ImportWorker`. Job insertion is idempotent and, when coupled to a state transition, occurs transactionally with the application record.

QuickTrain does not recreate generic Operations, Integrations, Audit, or DurableDelivery domains. The authoritative asset/import resources contain the product state; jobs only advance those state machines.

## Risks / Trade-offs

- **[More rows and joins than JSONB]** → Keep GraphQL reads explicit, add indexes on record/field/ordinal and latest-item revision paths, and benchmark representative imports before optimizing.
- **[Typed-child invariant crosses tables]** → Use a deferred PostgreSQL constraint trigger plus Ash transactional construction and tests that attempt invalid direct database states.
- **[Asset provider remains unselected]** → Keep the adapter narrow, ship deterministic development/test behavior, and fail startup or asset actions clearly when production storage is not configured.
- **[Partial imports complicate client recovery]** → Give every row a terminal outcome and stable identity; make batch and row retries idempotent.
- **[Row locking can serialize hot external keys]** → Lock only the targeted stable item and keep revision transactions short; unrelated items remain concurrent.
- **[The actor pipeline expands foundation scope]** → Implement it before product GraphQL actions, cover unauthenticated and cross-organization access, and avoid exposing broad foundation reads.
- **[Record envelope appears abstract for flat data]** → Keep its public API concrete and typed; the extra relationship buys an additive path to repeated and nested records that the product explicitly requires.

## Migration Plan

1. Add the exact stable Oban dependency and configuration required for product jobs, updating dependency files together.
2. Add the authenticated GraphQL actor pipeline and capability definitions with fail-closed tests before registering product domains in the schema.
3. Generate the Assets and Datasets Ash domains/resources, then deliberately refine attributes, actions, policies, relationships, identities, and GraphQL exposure.
4. Generate AshPostgres migrations and snapshots, including the deferred typed-child constraint trigger and indexes.
5. Add the storage behavior and deterministic development/test adapter.
6. Add asset lifecycle actions and verification worker.
7. Add schema publication, item revision, normalized record/value, and import actions and workers.
8. Run focused tests, `mise run openspec.validate`, and `mise run verify` from a clean migrated database.

Rollback before product data exists removes the new domains, jobs, and tables through the generated down migrations. After real assets or dataset revisions exist, rollback is an explicit product-data migration/export operation; it must not silently discard content or immutable provenance.

## Approved Cross-Change Architecture Record

This appendix preserves the approved design for later OpenSpec changes. It is non-normative for the current change and must be converted into capability specs and scoped tasks in each follow-up change. A later explicit user decision may revise it.

### A. Product domains and dependency direction

Approved product domains:

```text
QuickTrain.Assets
       │
       ▼
QuickTrain.Datasets ──┐
                      ├──▶ QuickTrain.Projects ──▶ QuickTrain.Tasks
QuickTrain.Forms ─────┘

QuickTrain.Finance and QuickTrain.Reputation integrate through named task
funding, settlement, and eligibility workflows rather than generic services.
```

- Assets own immutable content identity and storage access.
- Datasets own schemas, records, stable items, and revisions.
- Forms own reusable versioned task contracts.
- Projects bind one form version to one stable dataset cohort and configuration.
- Tasks own fetched selections, allocation, attempts, responses, review, and raw result evidence.
- Finance owns offers, reservations, ledger accounting, earnings, and payouts.
- Reputation owns global and organization-scoped rebuildable worker projections.
- Existing Accounts, Organizations, Authorization, and EnterpriseIdentity remain foundations.

Cross-domain workflows are named for their responsibility, such as `ProjectActivation`, `TaskGeneration` or selection, and work settlement. There is no generic Core, CRUD, Services, Operations, or DurableDelivery product layer.

### B. Forms are QuickTrain task contracts, not external integrations

There is no external-form import or externally hosted form flow in the approved first release. A customer imports or creates dataset content, then defines in QuickTrain how items are presented and what questions workers answer.

```text
Form
└── FormVersion
    ├── InputSlotDefinitions
    │   └── InputFieldRequirements
    ├── ordered PresentationElements
    ├── QuestionDefinitions
    ├── QuestionOptions
    └── LabelSets and Labels
```

A form version owns input slots, presentation elements, and questions together. It is editable as a draft and immutable after publication. Projects pin published versions.

The form declares typed reusable requirements instead of concrete dataset field IDs. A project maps requirements such as `candidate.body:text` to fields such as `response_text:text`. Activation validates type, cardinality, requiredness, and media compatibility and freezes the bindings.

Question renderer type is separate from answer value family. Radio, dropdown, pairwise, and image choice can share a selection representation; stars, Likert, and integer controls can share an integer representation. Static options and dynamic task-input options remain distinct relational references.

Form elements form one ordered presentation sequence with normalized subtypes for instructions, bound values, question placement, and structural headings/sections. Question-family constraints use typed resources rather than JSON configuration.

### C. Dataset content and task grouping are separate

Datasets contain atomic immutable item revisions. Forms describe required input slots and questions. A task selection can contain one or several dataset items:

```text
Single rating: subject × 1 → “Rate this response”
Pairwise:     candidate × 2 → “Which do you prefer?”
Group task:   candidate × N → ranking or other questions
```

The form and its questions are defined once. QuickTrain never creates a form or question copy for every dataset item.

### D. Projects freeze cohorts, bindings, and policies

An approved project pins:

- one organization;
- one dataset and an explicit cohort of immutable item revisions;
- one published form version;
- typed form-to-dataset bindings;
- grouping and selection configuration;
- worker audience and eligibility settings;
- automatic or manual review;
- per-question answer, skip, and escalation settings;
- coverage settings;
- and, when Finance is implemented, a rate/funding configuration.

Project lifecycle is `draft → active ⇄ paused → completed → archived`. Activation validates and freezes configuration. New dataset imports never silently enter an active project; managers explicitly enroll item revisions in a later cohort/batch.

### E. Both worker audiences and allocation modes are first-class

The global `User` remains the only account model. Organization membership is optional. Projects support `organization_members`, `external_users`, or `both` audiences without separate task or response tables.

External access initially supports open authenticated access and explicit allowlists, with future qualification/geography/reputation requirements as additive eligibility rules. Explicit blocks override positive routes. A user may qualify through membership and external eligibility simultaneously.

Work can be obtained by pool claim or direct assignment. Both routes create the same leased Attempt state machine and response model.

### F. Selection happens at fetch time; unused random groups are never persisted

The approved first release ships balanced and explicit selection. It does not precompute random tasks, store deterministic generation schedules, or materialize unused pairs.

On fetch or assignment:

1. Revalidate project, user, eligibility, and later funding.
2. Prefer an existing task that still needs accepted answers and has not already been attempted by that worker.
3. Otherwise select eligible project items at fetch time using the configured balanced policy or consume the next explicit group.
4. Create a lightweight Task and its exact TaskInputs only for the group actually issued.
5. Create the leased Attempt and record actual presentation order.

Persisting issued TaskInputs is required evidence of what the worker saw. Individual answers reference stable TaskInput IDs, never ambiguous display labels such as “A.”

Selection replication and item coverage are separate axes:

- Per-question accepted-answer targets control how many valid answers an exact task needs.
- Coverage settings control how often underlying items appear across tasks.

Single-item work often makes those equivalent. Pairwise work may prefer diverse balanced exposures with one response per pair, or repeated exact pairs for agreement/adjudication. The design supports both.

Future king-of-the-hill and Elo-style selection fit the fetch-time boundary. They may use accepted responses and mutable rebuildable rating projections to choose the next matchup. The first release only establishes the selection-strategy interface; it does not implement those adaptive strategies.

### G. Task, attempt, presentation, and response lifecycle

```text
Task
├── TaskInputs
├── TaskQuestionProgress projections
└── Attempts
    ├── AttemptInputPresentations
    └── one Response
        └── QuestionResponses
```

Task lifecycle is `open → satisfied`, with `needs_attention` after repeated skips or failures and `cancelled` on deliberate project closure. It remains open while any required question lacks enough accepted answers.

Attempt lifecycle covers assigned or claimed, in progress, submitted, expired, released, and cancelled states. Claims use leases. Pairwise/input randomization is recorded per attempt so canonical input identity and actual display order are both auditable.

There are not separate draft and submission tables. One Response moves from mutable `draft` to immutable `submitted`. Every question write locks and revalidates the draft parent; submission locks the same parent, validates all outcomes, and freezes it atomically. Rework creates a new linked attempt/response rather than rewriting evidence.

### H. Questions can be explicitly skipped

Missing, answered, and intentionally skipped are distinct states. Every applicable question must have an explicit QuestionResponse outcome before submission:

```text
QuestionResponse
├── answered → typed value children
└── skipped  → reason, optional explanation, skipped_at
```

The organization-owned project determines whether skipping is allowed for each question and whether a reason is required. Skips are immutable after submission and remain queryable even if a later attempt answers the same task/question.

A skip does not satisfy the question's accepted-answer target. Repeated skips eventually move task/question progress to `needs_attention` rather than circulating forever. By default a worker is not served the same task twice, but an organization may deliberately reassign a follow-up, which creates a new attempt.

### I. Typed response values and initial advanced annotations

Initial scalar/choice families:

- text;
- integer;
- decimal;
- boolean;
- static single and multiple choice;
- task-input single and multiple choice; and
- ordered task-input ranking.

The first release also includes bounding boxes, polygon and raster-mask segmentation, and text spans. Audio/video time ranges are explicitly out of scope.

```text
QuestionResponse
├── scalar typed answer
├── StaticOptionAnswers
├── TaskInputAnswers
├── BoundingBoxes
├── PolygonRegions → ordered PolygonPoints
├── MaskRegions → immutable mask Asset
└── TextSpans
```

Spatial and span records reference the exact TaskInput and source dataset value they annotate. Bounding boxes and polygon points use normalized coordinates. Raster masks reference immutable assets and source dimensions. Text spans reference immutable text values and use one explicitly documented offset convention validated at submission.

Dataset value persistence and answer persistence remain separate because they have different ownership, lifecycle, provenance, and policies. They may share code-level value-family validation conventions.

### J. Review, progress, and raw results

Projects support automatic and manual review. Review decisions are append-only and target QuestionResponses, allowing partial acceptance/rejection within one submitted Response. A batch action may review a whole Response while persisting per-question decisions.

Accepted answers, pending answers, skips, rejections, and escalation state are maintained in rebuildable `TaskQuestionProgress` projections. Normalized attempts, responses, question outcomes, and reviews remain authoritative.

There is no canonical-resolution/final-answer layer in the first release. QuickTrain returns all accepted QuestionResponses. It does not automatically select one worker answer, synthesize consensus geometry, or create an adjudicated truth record. A future resolution feature can be additive.

Organizations access results through paginated GraphQL and asynchronous immutable exports. Default exports contain accepted answers and exact task/input provenance. Audit exports may include skips, pending/rejected outcomes, expired attempts, review history, and organization-visible compensation. Structured JSONL or manifests are valid export formats even though PostgreSQL persistence contains no JSONB content.

### K. Finance is a separate correctness boundary

Approved `QuickTrain.Finance` concepts:

- rate configuration;
- concrete WorkOffers shown/frozen at fetch;
- FundingReservations tied to attempts;
- LedgerAccounts, balanced LedgerTransactions and LedgerPostings;
- WorkSettlements;
- worker Earnings; and
- external Payouts.

Organization price and worker payout are separate amounts. Future rate models may pay per accepted response, per accepted question, via base plus components, quality bonuses, qualification bands, or zero-cost internal work. The exact commercial model and payment provider remain intentionally unresolved for the Finance change.

Fetching paid work must reserve the maximum organization charge atomically so QuickTrain does not offer work it cannot pay for. Skips, rejections, and partial answers remain neutral task facts; the pinned rate terms determine monetary treatment. A worker's offer is frozen at fetch and cannot change retroactively.

Money uses integer minor units and explicit currencies, never floats. Ledger transactions balance within one currency. Corrections use reversal postings. Worker earnings and external payouts are separate so payout failure never erases earned money. Provider deposits, transfers, fees, refunds, disputes, and webhooks reconcile to the internal ledger with idempotency keys.

### L. Reputation is deliberately simple and rebuildable

The first reputation change adds one global and zero-or-more organization-scoped WorkerReputation projections per user. Dimensions may include quality, reliability, agreement, experience, accepted/rejected counts, skips, and expirations.

There are no reputation-policy tables, policy versions, per-organization formulas, duplicated reputation-event table, or ReputationAdjustment resource. Calculation is hardcoded in application code. Authoritative evidence already exists in Attempts, QuestionResponses, skips, ReviewDecisions, and future consensus/adjudication records.

If the formula changes, a future batch recalculation job rebuilds every profile. Corrections happen in authoritative task/review evidence and flow into recalculation.

Skipping is tracked but is not automatically a negative signal because it may indicate a bad question or unsuitable source data. Organizations may configure straightforward project admission thresholds against global or organization-scoped reputation, but they do not customize the calculation. Reputation-based dynamic compensation is deferred; any eventual rate quote remains frozen at fetch.

### M. Authorization and GraphQL boundaries for later domains

Organization management actions require an active account, active membership, and explicit capabilities such as datasets/forms/projects management, task review, and finance management.

Workers cannot browse arbitrary datasets or unallocated tasks. `fetch_work` performs eligibility and funding checks and returns a leased attempt. Dataset values/assets become readable only through that attempt. Draft responses are writable only by the attempt owner. Submitted evidence is immutable. Reviewers cannot edit worker answers.

All application API behavior is GraphQL except `/healthz`. APIs expose deliberate lifecycle actions rather than generic mutation of immutable revisions, tasks, responses, reviews, reputation projections, or ledger postings.

### N. Concurrency, idempotency, jobs, and verification

Fetch/claim runs in one transaction, locks existing task progress or candidate coverage rows with `FOR UPDATE SKIP LOCKED`, selects or creates one actual task, creates the attempt and presentation, and later creates the offer/reservation. Direct assignment follows the same path.

Every question write and submit action locks the Response parent. Review/settlement locks the QuestionResponse, progress, reservation, and ledger rows required for a single atomic decision. Import revisions lock the stable DatasetItem. Related-data validation happens after locks, not as an unsafe read-modify-write precheck.

Task progress, item coverage, adaptive ratings, and reputation are rebuildable projections. Accepted task evidence and ledger postings are authoritative.

Synchronous paths include fetch, draft save, submit, review, and ledger settlement. Oban handles large imports, asset processing, exports, projection reconciliation, provider collection/payouts, and webhook follow-through through responsibility-specific workers.

Tests must cover lifecycle actions, policies, GraphQL integration, normalized type constraints, immutable revisions, form bindings, selection invariants, concurrent claims, save/submit races, skip/escalation, review, geometry/span bounds, ledger balance/idempotency, reputation projections, exports, and job idempotency. Selection tests assert invariants rather than brittle exact random sequences. Concurrency tests use independent database connections and deliberate barriers. Every implementation change finishes with OpenSpec validation and `mise run verify`.

### O. Explicit first-release exclusions recorded across the design

- External or externally hosted forms.
- JSONB-backed dataset content or answer payloads.
- Customer-specific database tables.
- Arbitrary nested dataset records in the first dataset change, despite the additive record envelope.
- Precomputed/random task materialization or unused stored pairings.
- King-of-the-hill and Elo selection implementations; only their extension boundary is established.
- Audio/video range annotations.
- Automatic consensus, canonical resolution, or final-answer synthesis.
- Per-organization reputation formulas, reputation policy/version/adjustment/event tables.
- A final commercial rate model or payment provider in the core Tasks change.
- Frontend implementation.
