## Context

See `proposal.md` for why this record is separate from implementation changes.

The initial dataset/assets design accumulated approved decisions for four later product changes: `add-versioned-forms`, `add-project-task-collection`, `add-marketplace-finance`, and `add-worker-reputation`. Those decisions are valuable context, but keeping them in an implementation-focused change invited reviewers to treat deferred product architecture as current release scope.

This change has `skip_specs: true`. Everything below is a durable, non-normative starting point. A future change must select the relevant sections, resolve any then-current questions, and establish its own behavioral specs and tasks before implementation. A later explicit product decision may revise this record.

On 2026-09-12, the Projects and Tasks scope was promoted into [add-project-task-collection](../archive/2026-09-13-add-project-task-collection/proposal.md), with its own design, capability deltas, and implementation tasks. That proposal selects a new project for later enrollment, records offered question sets per attempt, and specifies immutable export snapshots. The user then selected core collection before detailed media: image presentation/choice, spatial answers, and mask uploads now belong to [add-project-task-media](../add-project-task-media/proposal.md). Only that follow-up depends on verified media support; core collection can be implemented and archived first. For the MVP, the user subsequently deferred proposal-added count/byte ceilings and mask quota accounting until actual usage informs them. The current [database-identities specification](../../specs/database-identities/spec.md) supersedes the archived proposal's PostgreSQL-generated identity design: use Ash `uuid_primary_key` for backend records and `Ash.UUID.generate/0` for internal UUIDs while retaining separate caller-supplied retry tokens. The dedicated proposals retain existing foundation behavior and published form constraints and govern their respective scope; core collection is now implemented with typed evidence, review, and sealed exports, while image-dependent execution remains deferred to the media change.

On 2026-10-05, the approved worker reputation system was promoted into [add-worker-reputation](../add-worker-reputation/proposal.md). That change owns its proposal, design, behavioral deltas, implementation tasks, competitor research, and future compensation integration contract. It supersedes the earlier fixed-only calculation, global/organization-only assessment scope, and deferral of reputation-based pay. Reputation is planned, not implemented; Finance remains separately scoped.

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
- Reputation owns project, organization, and platform-controlled global worker assessments as rebuildable projections.
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

Form elements form one ordered presentation sequence. Following the `add-versioned-forms` architecture review, kind-specific text and bound-value/question references live on PresentationElement itself; separate presentation-subtype identities are unnecessary. Dynamic input-slot and optional image-source references live directly on QuestionDefinition, remaining distinct from static options. Question-family constraints use typed resources rather than JSON configuration and are inspected through their owning question.

Future Projects and Tasks retain stable FormVersion, InputFieldRequirement, QuestionDefinition, QuestionOption, Label, and PresentationElement references. Attempt-specific input presentation remains owned by Tasks. No planned consumer references the retired presentation-subtype or input-source wrapper IDs. Worker reads still require the separate attempt-ownership path described in section M.

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
- when Reputation is implemented, resolved reputation settings and enforcement actions;
- automatic or manual review;
- per-question answer, skip, and escalation settings;
- coverage settings; and
- when Finance is implemented, a rate and funding configuration.

Project lifecycle permits `draft -> active`, `active <-> paused`, either `active -> completed` or `paused -> completed`, and `completed -> archived`. Completion does not require an otherwise unnecessary pause. Activation validates and freezes configuration. New dataset imports never silently enter an active project. The original record left later enrollment unresolved; `add-project-task-collection` now selects a new project with its own cohort and configuration, preserving every existing task and attempt's original contract without adding configuration snapshots or enrollment batches.

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

The original plan grouped bounding boxes, polygon/raster-mask segmentation, and text spans in the first task-response release. The revised release order keeps text spans in `add-project-task-collection` and moves image-dependent execution and spatial answers to `add-project-task-media` after detailed media support. The combined eventual model below is preserved; it is not an acceptance gate for core collection. Audio and video time ranges remain explicitly out of scope.

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

Optional reputation-based pay bands, quality bonuses, and their frozen-offer requirements are recorded in [the reputation change's Finance integration contract](../add-worker-reputation/design.md#6-keep-compensation-commitments-in-finance). Finance owns offers, maximum-charge reservations, settlement, and payouts; that integration does not make Finance a prerequisite for reputation.

Money uses integer minor units and explicit currencies, never floats. Ledger transactions balance within one currency. Corrections use reversal postings. Worker earnings and external payouts are separate so payout failure never erases earned money. Provider deposits, transfers, fees, refunds, disputes, and webhooks reconcile to the internal ledger with idempotency keys.

### L. Reputation is owned by its dedicated change

[add-worker-reputation](../add-worker-reputation/proposal.md) owns known-answer checks, repeated peer disagreement, scoped assessments, organization defaults/project overrides, reviewer information, and recoverable new-work restrictions. Its [design](../add-worker-reputation/design.md) retains the approved compensation integration terms and competitor research; its [specs](../add-worker-reputation/specs/worker-reputation/spec.md) and [tasks](../add-worker-reputation/tasks.md) govern future implementation. This record retains the cross-domain boundary only and does not maintain a second reputation plan.

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
- Canonical resolution or final-answer synthesis. Derived peer-agreement measurements for reputation are permitted by section L.
- Customer-authored reputation formulas, generic policy/version engines, arbitrary reputation adjustments, or duplicate reputation-event streams. The dedicated reputation change owns scoped settings, answer-key provenance, and future offer integration.
- A final commercial rate model or payment provider in the core Tasks change.
- Frontend implementation.

## Risks / Trade-offs

- **[Deferred decisions may become stale]** -> Each future change must revalidate the relevant sections against current product evidence before treating them as requirements.
- **[A broad record can look normative]** -> `skip_specs: true`, the proposal non-goals, and this context explicitly make it non-normative and non-blocking.
- **[Future changes may duplicate text]** -> Duplication is intentional when converting a selected decision into a self-contained capability contract; this record remains historical context.

## Migration Plan

There is no runtime migration. When a future domain is selected, create or update its dedicated OpenSpec change, cite the relevant decisions from this record, revise them where product evidence requires, and leave unrelated sections deferred.

## Deferred file interpretation and HTTP storage integration

Approved on 2026-09-09: MVP assets are opaque downloads. Restore format sniffing,
image dimensions, bounded decoding, sanitization, or previews only when a concrete
Forms or Tasks rendering requirement needs them. Readiness currently certifies
size/hash integrity and immutability, never decodability or safe rendering.

Before introducing inline rendering, define the supported formats, isolated serving
origin, parser/decoder choice, resource limits, and response-header policy in a
separate scoped change. Prefer a maintained library over handwritten format parsers;
do not restore the PNG/JPEG/GIF/PDF branches merely for theoretical completeness.

A reachable development/production HTTP storage adapter also remains unselected.
That change must prove provider-enforced upload caps, immutable publication, direct
nonredirecting endpoints, and download responses with attachment disposition,
application/octet-stream, and nosniff. The in-memory test double does not provide
HTTP endpoints. These are deferred requirements, not implementation tasks here.
