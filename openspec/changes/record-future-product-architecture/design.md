## Context

See `proposal.md` for why this record is separate from implementation changes.

The initial dataset/assets design accumulated approved decisions for four later product changes: `add-versioned-forms`, `add-project-task-collection`, `add-marketplace-finance`, and `add-worker-reputation`. Those decisions are valuable context, but keeping them in an implementation-focused change invited reviewers to treat deferred product architecture as current release scope.

This change has `skip_specs: true`. Everything below is a durable, non-normative starting point. A future change must select the relevant sections, resolve any then-current questions, and establish its own behavioral specs and tasks before implementation. A later explicit product decision may revise this record.

## Goals / Non-Goals

**Goals:**

- Preserve every approved cross-change decision in OpenSpec.
- Keep future domain boundaries and dependency direction discoverable.
- Prevent deferred architecture from becoming an accidental prerequisite or acceptance criterion for current changes.

**Non-Goals:**

- Define current runtime behavior or an implementation plan.
- Create placeholder resources, tables, APIs, jobs, or dependencies.
- Freeze commercial, payment-provider, or later selection-policy decisions that were deliberately left open.

## Decisions

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

Cross-domain workflows are named for their responsibility, such as `ProjectActivation`, `TaskSelection`, and `WorkSettlement`. There is no generic Core, CRUD, Services, Operations, or DurableDelivery product layer.

### B. Forms are QuickTrain task contracts, not external integrations

There is no external-form import or externally hosted form flow in the planned first release. A customer imports or creates dataset content, then defines in QuickTrain how items are presented and what questions workers answer.

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

Form elements form one ordered presentation sequence with normalized subtypes for instructions, bound values, question placement, and structural headings or sections. Question-family constraints use typed resources rather than JSON configuration.

### C. Dataset content and task grouping are separate

Datasets contain atomic immutable item revisions. Forms describe required input slots and questions. A task selection can contain one or several dataset items:

```text
Single rating: subject × 1 -> "Rate this response"
Pairwise:     candidate × 2 -> "Which do you prefer?"
Group task:   candidate × N -> ranking or other questions
```

The form and its questions are defined once. QuickTrain never creates a form or question copy for every dataset item.

### D. Projects freeze cohorts, bindings, and policies

A planned project pins:

- one organization;
- one dataset and an explicit cohort of immutable item revisions;
- one published form version;
- typed form-to-dataset bindings;
- grouping and selection configuration;
- worker audience and eligibility settings;
- automatic or manual review;
- per-question answer, skip, and escalation settings;
- coverage settings; and
- when Finance is implemented, a rate and funding configuration.

Project lifecycle permits `draft -> active`, `active <-> paused`, either `active -> completed` or `paused -> completed`, and `completed -> archived`. Completion does not require an otherwise unnecessary pause. Activation validates and freezes configuration. New dataset imports never silently enter an active project. Whether later enrollment creates another immutable project-configuration snapshot or a separately configured batch is intentionally unresolved for the future Projects change; that change must choose one model and ensure every existing task and attempt remains bound to its original cohort and frozen configuration.

### E. Both worker audiences and allocation modes are first-class

The global `User` remains the only account model. Organization membership is optional. Projects support `organization_members`, `external_users`, or `both` audiences without separate task or response tables.

External access initially supports open authenticated access and explicit allowlists, with future qualification, geography, and reputation requirements as additive eligibility rules. This is a named project-worker eligibility path, not the shared organization-capability path: it requires an active global user, active organization, active project, and a matching project audience route. The `organization_members` route additionally requires active membership; the `external_users` route applies the project's external-access and allowlist rules without requiring membership; and `both` accepts either route. Explicit blocks override positive routes, and a user may qualify through both simultaneously. A bearer session or open audience setting alone grants no dataset, asset, task, or project browsing authority.

Work can be obtained by pool claim or direct assignment. Both routes create the same leased Attempt state machine and response model.

### F. Selection happens at fetch time

The planned first release ships balanced and explicit selection. It does not precompute random tasks, store deterministic generation schedules, or materialize unused pairs.

On fetch or assignment:

1. Revalidate project, user, eligibility, and later funding.
2. Prefer an existing task that still needs accepted answers and has not already been attempted by that worker.
3. Otherwise select eligible project items at fetch time using the configured balanced policy or consume the next explicit group.
4. Create a lightweight Task and its exact TaskInputs only for the group actually issued.
5. Create the leased Attempt and record actual presentation order.

Persisting issued TaskInputs is required evidence of what the worker saw. Individual answers reference stable TaskInput IDs, never ambiguous display labels such as `A`.

Selection replication and item coverage are separate axes:

- Per-question accepted-answer targets control how many valid answers an exact task needs.
- Coverage settings control how often underlying items appear across tasks.

Single-item work often makes those equivalent. Pairwise work may prefer diverse balanced exposures with one response per pair, or repeated exact pairs for agreement and adjudication. The design supports both.

Future king-of-the-hill and Elo-style selection fit the fetch-time boundary. They may use accepted responses and mutable rebuildable rating projections to choose the next matchup. The first task-selection change should establish the strategy interface while shipping only balanced and explicit selection.

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

Task lifecycle is `open -> satisfied`, with `needs_attention` after repeated skips or failures and `cancelled` on deliberate project closure. It remains open while any required question lacks enough accepted answers.

Attempt lifecycle covers assigned or claimed, in progress, submitted, expired, released, and cancelled states. Claims use leases. Pairwise or input randomization is recorded per attempt so canonical input identity and actual display order are both auditable.

There are not separate draft and submission tables. One Response moves from mutable `draft` to immutable `submitted`. Every question write locks and revalidates the draft parent; submission locks the same parent, validates all outcomes, and freezes it atomically. Rework creates a new linked attempt and response rather than rewriting evidence.

### H. Questions can be explicitly skipped

Missing, answered, and intentionally skipped are distinct states. Every applicable question must have an explicit QuestionResponse outcome before submission:

```text
QuestionResponse
├── answered -> typed value children
└── skipped  -> reason, optional explanation, skipped_at
```

The organization-owned project determines whether skipping is allowed for each question and whether a reason is required. Skips are immutable after submission and remain queryable even if a later attempt answers the same task and question.

A skip does not satisfy the question's accepted-answer target. Repeated skips eventually move task or question progress to `needs_attention` rather than circulating forever. By default a worker is not served the same task twice, but an organization may deliberately reassign a follow-up, which creates a new attempt.

### I. Typed response values and initial advanced annotations

Initial scalar and choice families:

- text;
- integer;
- decimal;
- boolean;
- static single and multiple choice;
- task-input single and multiple choice; and
- ordered task-input ranking.

The first task-response release also includes bounding boxes, polygon and raster-mask segmentation, and text spans. Audio and video time ranges are explicitly out of scope.

```text
QuestionResponse
├── scalar typed answer
├── StaticOptionAnswers
├── TaskInputAnswers
├── BoundingBoxes
├── PolygonRegions -> ordered PolygonPoints
├── MaskRegions -> immutable mask Asset
└── TextSpans
```

Spatial and span records reference the exact TaskInput and source dataset value they annotate. Bounding boxes and polygon points use normalized coordinates. Raster masks reference immutable assets and source dimensions. Text spans reference immutable text values and use one explicitly documented offset convention validated at submission.

Dataset value persistence and answer persistence remain separate because they have different ownership, lifecycle, provenance, and policies. They may share code-level value-family validation conventions.

### J. Review, progress, and raw results

Projects support automatic and manual review. Review decisions are append-only and target QuestionResponses, allowing partial acceptance or rejection within one submitted Response. A batch action may review a whole Response while persisting per-question decisions.

Accepted answers, pending answers, skips, rejections, and escalation state are maintained in rebuildable `TaskQuestionProgress` projections. Normalized attempts, responses, question outcomes, and reviews remain authoritative.

There is no canonical-resolution or final-answer layer in the first task release. QuickTrain returns all accepted QuestionResponses. It does not automatically select one worker answer, synthesize consensus geometry, or create an adjudicated truth record. A future resolution feature can be additive.

Organizations access results through paginated GraphQL and asynchronous immutable exports. Default exports contain accepted answers and exact task and input provenance. Audit exports may include skips, pending or rejected outcomes, expired attempts, review history, and organization-visible compensation. Structured JSONL or manifests are valid export formats even though PostgreSQL persistence contains no JSONB content.

### K. Finance is a separate correctness boundary

Approved `QuickTrain.Finance` concepts:

- rate configuration;
- concrete WorkOffers shown and frozen at fetch;
- FundingReservations tied to attempts;
- LedgerAccounts, balanced LedgerTransactions, and LedgerPostings;
- WorkSettlements;
- worker Earnings; and
- external Payouts.

Organization price and worker payout are separate amounts. Future rate models may pay per accepted response, per accepted question, via base plus components, quality bonuses, qualification bands, or zero-cost internal work. The exact commercial model and payment provider remain intentionally unresolved for the Finance change.

Fetching paid work must reserve the maximum organization charge atomically so QuickTrain does not offer work it cannot pay for. Skips, rejections, and partial answers remain neutral task facts; the pinned rate terms determine monetary treatment. A worker's offer is frozen at fetch and cannot change retroactively.

Money uses integer minor units and explicit currencies, never floats. Ledger transactions balance within one currency. Corrections use reversal postings. Worker earnings and external payouts are separate so payout failure never erases earned money. Provider deposits, transfers, fees, refunds, disputes, and webhooks reconcile to the internal ledger with idempotency keys.

### L. Reputation is deliberately simple and rebuildable

The first reputation change adds one global and zero-or-more organization-scoped WorkerReputation projections per user. Dimensions may include quality, reliability, agreement, experience, accepted or rejected counts, skips, and expirations.

There are no reputation-policy tables, policy versions, per-organization formulas, duplicated reputation-event table, or ReputationAdjustment resource. Calculation is hardcoded in application code. Authoritative evidence already exists in Attempts, QuestionResponses, skips, ReviewDecisions, and future consensus or adjudication records.

If the formula changes, a future batch recalculation job rebuilds every profile. Corrections happen in authoritative task and review evidence and flow into recalculation.

Skipping is tracked but is not automatically a negative signal because it may indicate a bad question or unsuitable source data. Organizations may configure straightforward project admission thresholds against global or organization-scoped reputation, but they do not customize the calculation. Reputation-based dynamic compensation is deferred; any eventual rate quote remains frozen at fetch.

### M. Authorization and GraphQL boundaries for later domains

Organization management actions use the shared organization-capability path and require an active account, active organization, active membership, and explicit capabilities such as dataset, form, and project management, task review, and finance management.

Worker actions use the separate project-worker eligibility and attempt-ownership path that the future Projects and Tasks capabilities must specify normatively. `fetch_work` requires an active account, organization, and project, then applies the configured audience route, eligibility, explicit blocks, and funding checks; only the organization-member route requires membership. Workers cannot browse arbitrary datasets or unallocated tasks. A successful fetch returns a leased attempt, and only that attempt relationship grants its owner narrowly scoped reads of the allocated dataset values and assets plus writes to its draft response. Submitted evidence is immutable. Reviewers cannot edit worker answers.

All application API behavior is GraphQL except `/healthz`. APIs expose deliberate lifecycle actions rather than generic mutation of immutable revisions, tasks, responses, reviews, reputation projections, or ledger postings.

### N. Concurrency, idempotency, jobs, and verification

Fetch or claim runs in one transaction, locks existing task progress or candidate coverage rows with `FOR UPDATE SKIP LOCKED`, selects or creates one actual task, creates the attempt and presentation, and later creates the offer and reservation. Direct assignment follows the same path.

Every question write and submit action locks the Response parent. Review and settlement lock the QuestionResponse, progress, reservation, and ledger rows required for a single atomic decision. Import revisions lock the stable DatasetItem. Related-data validation happens after locks, not as an unsafe read-modify-write precheck.

Task progress, item coverage, adaptive ratings, and reputation are rebuildable projections. Accepted task evidence and ledger postings are authoritative.

Synchronous paths include fetch, draft save, submit, review, and ledger settlement. Oban handles large imports, asset processing, exports, projection reconciliation, provider collection or payouts, and webhook follow-through through responsibility-specific workers.

Future tests cover lifecycle actions, policies, GraphQL integration, normalized type constraints, immutable revisions, form bindings, selection invariants, concurrent claims, save or submit races, skip and escalation, review, geometry and span bounds, ledger balance and idempotency, reputation projections, exports, and job idempotency. Selection tests assert invariants rather than brittle exact random sequences. Concurrency tests use independent database connections and deliberate barriers.

### O. Explicit exclusions preserved for future changes

- External or externally hosted forms.
- JSONB-backed dataset content or answer payloads.
- Customer-specific database tables.
- Arbitrary nested dataset records in the first dataset change, despite the additive record envelope.
- Precomputed random task materialization or unused stored pairings.
- King-of-the-hill and Elo selection implementations; only their extension boundary is established initially.
- Audio or video range annotations.
- Automatic consensus, canonical resolution, or final-answer synthesis.
- Per-organization reputation formulas or reputation policy, version, adjustment, or duplicate event tables.
- A final commercial rate model or payment provider in the core Tasks change.
- Frontend implementation.

## Risks / Trade-offs

- **[Deferred decisions may become stale]** -> Each future change must revalidate the relevant sections against current product evidence before treating them as requirements.
- **[A broad record can look normative]** -> `skip_specs: true`, the proposal non-goals, and this context explicitly make it non-normative and non-blocking.
- **[Future changes may duplicate text]** -> Duplication is intentional when converting a selected decision into a self-contained capability contract; this record remains historical context.

## Migration Plan

There is no runtime migration. When a future domain is selected, create or update its dedicated OpenSpec change, cite the relevant decisions from this record, revise them where product evidence requires, and leave unrelated sections deferred.
