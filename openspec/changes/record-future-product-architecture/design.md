## Context

See `proposal.md` for why this record is separate from implementation changes.

The initial dataset/assets design accumulated approved decisions for four later product changes: `add-versioned-forms`, `add-project-task-collection`, `add-marketplace-finance`, and `add-worker-reputation`. Those decisions are valuable context, but keeping them in an implementation-focused change invited reviewers to treat deferred product architecture as current release scope.

This change has `skip_specs: true`. Everything below is a durable, non-normative starting point. A future change must select the relevant sections, resolve any then-current questions, and establish its own behavioral specs and tasks before implementation. A later explicit product decision may revise this record.

On 2026-09-12, the Projects and Tasks scope was promoted into [add-project-task-collection](../archive/2026-09-13-add-project-task-collection/proposal.md), with its own design, capability deltas, and implementation tasks. That proposal selects a new project for later enrollment, records offered question sets per attempt, and specifies immutable export snapshots. The user then selected core collection before detailed media: image presentation/choice, spatial answers, and mask uploads now belong to [add-project-task-media](../add-project-task-media/proposal.md). Only that follow-up depends on verified media support; core collection can be implemented and archived first. For the MVP, the user subsequently deferred proposal-added count/byte ceilings and mask quota accounting until actual usage informs them. The current [database-identities specification](../../specs/database-identities/spec.md) supersedes the archived proposal's PostgreSQL-generated identity design: use Ash `uuid_primary_key` for backend records and `Ash.UUID.generate/0` for internal UUIDs while retaining separate caller-supplied retry tokens. The dedicated proposals retain existing foundation behavior and published form constraints and govern their respective scope; core collection is now implemented with typed evidence, review, and sealed exports, while image-dependent execution remains deferred to the media change.

On 2026-10-05, worker reputation, project access restrictions, and reputation-based compensation were approved for documentation after competitor research. Sections K and L record those decisions and supersede the earlier fixed-only reputation calculation, global/organization-only profile scope, and deferral of dynamic compensation. This approval records future product direction; it does not implement Reputation or Finance or change the current collection contract.

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

Optional reputation-based pay bands and quality bonuses are approved. Organizations provide defaults and projects may override them; activation resolves and freezes the project's rate rules. A project may offer a standard rate and higher rates to workers with sufficiently established project- or organization-scoped quality evidence. Initial pay upgrades use known-answer accuracy and substantive human review, with minimum evidence requirements. Peer agreement remains a monitoring and eligibility signal until its suitability for compensation has been established for that project. Public competitor pay amounts and thresholds are not QuickTrain defaults.

Historical reputation selects the rate for the next offer. A quality bonus can reward performance on the offered work according to criteria disclosed with that offer. Eligibility for better-paid projects is a separate use of reputation and does not imply a different rate for identical work. Access restrictions, answer acceptance/rejection, and monetary settlement remain separate decisions.

Fetching paid work must reserve the maximum organization charge atomically, including any promised conditional bonus, so QuickTrain does not offer work it cannot pay for. Skips, rejections, and partial answers remain neutral task facts; the pinned rate terms determine monetary treatment. A worker's quoted rate and any bonus criteria are shown and frozen at fetch, along with enough evidence to explain the selected band. Later reputation or configuration changes affect future offers; they cannot change an issued offer's quoted rate or bonus rules.

Money uses integer minor units and explicit currencies, never floats. Ledger transactions balance within one currency. Corrections use reversal postings. Worker earnings and external payouts are separate so payout failure never erases earned money. Provider deposits, transfers, fees, refunds, disputes, and webhooks reconcile to the internal ledger with idempotency keys.

### L. Reputation uses explainable, scoped, rebuildable signals

#### Evidence and assessment scope

WorkerReputation is a rebuildable assessment of the existing global User. Project reputation is the most specific assessment, organization reputation summarizes evidence within that organization, and a global assessment follows platform-controlled rules for eligible evidence and calculation. Locally configured scores are not averaged into a global score, and one organization's settings cannot rewrite another organization's assessment or the global calculation.

Keep known-answer accuracy, substantive human review, peer agreement, reliability, and experience distinguishable, even when a configured calculation combines signals. Show the contributing counts and evidence window with a score, such as 46 of 50 known-answer checks passed. Insufficient history means unknown or provisional, not poor quality or established excellence. Known-answer correctness carries more weight than peer agreement. Strong correctness evidence paired with unusual disagreement should prompt investigation before a strong penalty.

Attempts, submitted QuestionResponses, skips, ReviewDecisions, and the known-answer keys described below are authoritative evidence. Preserve review provenance: under the current [task-review contract](../../specs/task-review/spec.md), automatic review accepts every answered submission, so those acceptances do not count as independent positive quality judgments. A rejection is likewise a review fact, not a substitute for an answer key. Skips remain visible but are not automatically negative because they may reflect unsuitable source data or a bad question.

#### Organization-authored known-answer checks

Organizations can include quality-check questions among ordinary work in a batch/project and provide the expected answers. Each key belongs to the exact published question and immutable task input revisions, including the relevant option/input identities. A reusable form question alone cannot identify the correct answer for every dataset item. Checks use the ordinary worker presentation; their designation and answer keys are hidden from worker-facing responses and GraphQL traversal.

Use the existing typed answer families with deliberate matching rules: exact matching for objectively checkable choices and booleans, and configured tolerance for numeric answers. Begin with objectively checkable answers. Free-text semantic grading and spatial matching require separately specified grading behavior before contributing to reputation; no universal text or geometry comparator is implied.

Preserve the key and matching rule used for an evaluation. Authorized corrections or disabling a faulty key retain its prior provenance, recalculate affected assessments, and reevaluate restrictions. Worker submissions remain immutable. Widespread missed or contested checks should surface potential key or instruction problems for organization review, alongside individual worker quality concerns.

#### Persistent peer disagreement

Compare distinct workers' submitted answers to the same question and exact task inputs under the same pinned contract. Exclude the assessed worker's own answer and prevent repeat attempts from giving one peer multiple votes. Compare stable input identities rather than randomized display labels. Skips and absent answers do not count as disagreeing answers.

A comparison contributes only after a minimum number of peers have answered and the other workers agree strongly enough. Ties, split opinion, and sparse evidence provide no negative signal. For example, disagreement with nine peers choosing A and one choosing B is more informative than a five-to-five split; these numbers illustrate the principle and are not default thresholds. Numeric comparisons use a robust center such as the median and an appropriate tolerance. Free text and spatial annotations need separately designed comparison rules.

Measure repeated disagreement over recent comparable answers, with a minimum worker sample and a bounded, weaker contribution than known-answer accuracy. A single unusual answer does not establish poor reputation. Agreement measures consistency and cannot by itself establish correctness, particularly on subjective preference questions. Subjective projects can disable its contribution and enforcement.

This is a derived quality signal, not a canonical-answer or adjudication layer. It does not select a final answer, rewrite responses, or reject individual submissions. Collection completion remains governed by the current [submission-target and review contract](../../specs/task-review/spec.md); reputation does not create replacement demand or reopen satisfied tasks.

#### Organization defaults and project overrides

Use one application-owned calculation with a small set of typed settings. Organizations provide defaults; projects can override them to suit task semantics. Resolve and freeze the effective project configuration at activation, consistent with the [project contract](../../specs/projects/spec.md). Later organization-default edits do not silently alter active projects.

| Setting | Purpose |
| --- | --- |
| Enabled signals and bounded weights | Choose contributions while keeping agreement weaker than known-answer correctness |
| Minimum evidence | Require sufficient worker history and peer samples before meaningful scoring or enforcement |
| Agreement threshold and numeric tolerance | Distinguish meaningful disagreement from ambiguity and small differences |
| Recent-history window | Let improvement affect the assessment |
| Admission thresholds and evidence scope | Select the qualifying assessment and minimum standard for future work |
| Action per signal | Inform reviewers or suspend new project work |

Store direct settings and the evidence needed to explain evaluations. There is no customer-authored formula language, general reputation-policy engine or version-table hierarchy, duplicate reputation-event stream, or arbitrary ReputationAdjustment resource. Retained answer-key provenance, frozen project configuration, and immutable WorkOffers serve their own responsibilities. Correct evidence through its owning workflow; rebuild projections after corrections or application calculation changes.

#### Project access restrictions and recovery

Support both informing organization reviewers and automatic suspension from new project work. Known-answer failures may trigger configured automatic suspension after the minimum evidence requirement is met. Persistent disagreement defaults to informing reviewers, with explicit project opt-in to automatic suspension where agreement is an appropriate quality measure. Each signal's enforcement action is independent of whether it contributes to the displayed assessment.

Enforce suspensions on both fetch and direct assignment. The automatic restriction is scoped to the project, not a platform-wide ban. A reputation-only suspension does not revoke already issued attempts, reject their submissions, erase accepted results, or change promised pay. Existing account, organization, audience, explicit-block, lifecycle, ownership, and lease rules still govern those attempts.

Make the reason and supporting evidence available to authorized organization reviewers, support deliberate reinstatement, and reevaluate restrictions when faulty keys or reviews are corrected. Worker-facing explanations must not disclose hidden keys or other workers' answers. Reviewer inspection remains limited to evidence they are authorized to access within the organization; neither view grants access to another organization's private evidence. Ordinary reputation scores and restrictions remain separate from platform account enforcement.

#### Compensation integration

Section K owns optional project pay bands, quality bonuses, and frozen offers. Reputation supplies scoped evidence for quoting; Finance owns the offer, maximum funding reservation, settlement, and payment. A later score change can alter future eligibility or future pay offers while preserving issued financial commitments.

#### Research rationale and implementation follow-up

The following first-party sources were reviewed on 2026-10-05. They explain the selected capabilities; their numeric thresholds, irreversible exclusions, and commercial terms are not adopted as QuickTrain requirements.

- [Appen Quality Flow](https://success.appen.com/appen-success-center/settings/guide-to-test-questions-in-quality-flow) couples known-answer accuracy with job access and restores scores/access after faulty keys are corrected. Its [test-question guidance](https://success.appen.com/appen-success-center/settings/guide-to-test-questions-in-quality-flow/test-question-best-practices) also describes pausing a job when widespread failures and contests indicate potential question problems. This supports recoverable enforcement and review of question quality.
- [Toloka Quorum](https://platform.toloka.ai/docs/reference/nodes/quorum/) demonstrates automatic exclusion from future work for repeated disagreement, separately from grading existing answers. [MTurk eligibility](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMechanicalTurkRequester/SelectingEligibleWorkers.html) and [consensus policies](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMturkAPI/ApiReference_HITReviewPolicies.html) separate access requirements from optional scoring actions and exclude inconclusive questions from worker agreement scores.
- [Labelbox's quality strategy](https://labelbox.com/guides/how-to-create-a-quality-strategy-for-your-data-labeling-project/) emphasizes investigation, feedback, and retraining and distinguishes subjective agreement from accuracy. [Prolific's quality controls](https://researcher-help.prolific.com/en/articles/445223-bulk-rejecting-exceptionally-fast-submissions) illustrate reviewer information with optional automation. These support a review-only action and conservative disagreement defaults.
- [Toloka's marketplace pricing documentation](https://github.com/Toloka/docs/blob/main/en/guide/concepts/dynamic-pricing.md) describes skill-dependent pay bands fixed at assignment. This is an older marketplace precedent; availability in its newer node-based platform was not confirmed. [MTurk bonuses](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMechanicalTurkRequester/IntroCoreConcepts.html) and [Prolific performance payments](https://researcher-help.prolific.com/en/articles/445234-can-i-make-partial-payments-to-participants) support base pay plus performance bonuses. [Remotasks](https://www.remotasks.com/en/projects/90551) describes quality unlocking better-paid tasks. [Outlier](https://outlier.ai/) advertises quality-based rewards but does not expose a precise historical-score-to-rate formula in the public pages reviewed. These are distinct compensation mechanisms, not evidence for one universal reputation multiplier.

Future Reputation and Finance changes must turn these approved directions into behavioral specs and implementation tasks. Exact formulas, numerical thresholds, windows, cold-start admission behavior, global evidence eligibility, correction/reinstatement semantics, supported grading families, review notifications, and pay-band/bonus schedules remain to be specified there. This record does not invent default values or a generic policy framework to settle those details.

### M. Authorization and GraphQL boundaries for later domains

Organization management actions use the shared organization-capability path and require an active account, active organization, active membership, and explicit capabilities such as dataset, form, and project management, task review, and finance management.

Reputation settings, answer-key authoring/correction, assessment inspection, and reinstatement use explicit organization scope and appropriate management or review authority. Project/organization assessments and their underlying evidence are private to authorized readers in that scope. Global summaries follow platform-defined disclosure rules and do not grant access to another organization's raw evidence. Known-answer keys and check designations are excluded from worker work bundles and nested GraphQL reads.

Worker actions use the separate project-worker eligibility and attempt-ownership path that the future Projects and Tasks capabilities must specify normatively. `fetch_work` requires an active account, organization, and project, then applies the configured audience route, eligibility, explicit blocks, and funding checks; only the organization-member route requires membership. Workers cannot browse arbitrary datasets or unallocated tasks. A successful fetch returns a leased attempt, and only that attempt relationship grants its owner narrowly scoped reads of the allocated dataset values and assets plus writes to its draft response. Submitted evidence is immutable. Reviewers cannot edit worker answers.

All application API behavior is GraphQL except `/healthz`. APIs expose deliberate lifecycle actions rather than generic mutation of immutable revisions, tasks, responses, reviews, reputation projections, or ledger postings.

The reputation suspension in section L is a new-work eligibility check. Future implementation must keep it distinct from the continuing authorization checks on an existing attempt, so an automatic score change does not cancel previously issued work.

### N. Concurrency, idempotency, jobs, and verification

Fetch or claim runs in one transaction, locks existing task progress or candidate coverage rows with `FOR UPDATE SKIP LOCKED`, selects or creates one actual task, creates the attempt and presentation, and later creates the offer and reservation. Direct assignment follows the same path.

Every question write and submit action locks the Response parent. Review and settlement lock the QuestionResponse, progress, reservation, and ledger rows required for a single atomic decision. Import revisions lock the stable DatasetItem. Related-data validation happens after locks, not as an unsafe read-modify-write precheck.

Task progress, item coverage, adaptive ratings, and reputation are rebuildable projections. Accepted task evidence and ledger postings are authoritative.

Future reputation integration must serialize allocation with applicable restriction changes and atomically pin the reputation-based rate and funding reservation when issuing an offer. Key/review corrections and assessment rebuilds must converge without duplicate effects or stale overwrites. The implementation change must define projection freshness and race handling so delayed scoring cannot silently defeat configured access rules, while issued offers retain their original terms.

Synchronous paths include fetch, draft save, submit, review, and ledger settlement. Oban handles large imports, asset processing, exports, projection reconciliation, provider collection or payouts, and webhook follow-through through responsibility-specific workers.

Future tests cover lifecycle actions, policies, GraphQL integration, normalized type constraints, immutable revisions, form bindings, selection invariants, concurrent claims, save or submit races, skip and escalation, review, geometry and span bounds, ledger balance and idempotency, reputation projections, exports, and job idempotency. Selection tests assert invariants rather than brittle exact random sequences. Concurrency tests use independent database connections and deliberate barriers.

Reputation/Finance verification must additionally cover hidden-key reads, exact-input matching, provisional histories, sparse or split peer evidence, self/duplicate-vote exclusion, automatic versus substantive review provenance, project-default freezing, scoped suspension and reinstatement, corrected-key recalculation, allocation/restriction races, and frozen pay/bonus terms across later score changes. These are future verification requirements, not implementation tasks for this documentation-only change.

### O. Explicit exclusions preserved for future changes

- External or externally hosted forms.
- JSONB-backed dataset content or answer payloads.
- Customer-specific database tables.
- Arbitrary nested dataset records in the first dataset change, despite the additive record envelope.
- Precomputed random task materialization or unused stored pairings.
- King-of-the-hill and Elo selection implementations; only their extension boundary is established initially.
- Audio or video range annotations.
- Canonical resolution or final-answer synthesis. Derived peer-agreement measurements for reputation are permitted by section L.
- Customer-authored reputation formulas, generic policy/version engines, arbitrary reputation adjustments, or duplicate reputation-event streams. Direct scoped settings, answer-key provenance, and frozen offer terms are permitted by sections K and L.
- A final commercial rate model or payment provider in the core Tasks change.
- Frontend implementation.

## Risks / Trade-offs

- **[Deferred decisions may become stale]** -> Each future change must revalidate the relevant sections against current product evidence before treating them as requirements.
- **[A broad record can look normative]** -> `skip_specs: true`, the proposal non-goals, and this context explicitly make it non-normative and non-blocking.
- **[Future changes may duplicate text]** -> Duplication is intentional when converting a selected decision into a self-contained capability contract; this record remains historical context.
- **[Majority agreement can reward conformity]** -> Require enough distinct peers and clear agreement, keep the signal weaker than known-answer correctness, and default disagreement enforcement to reviewer information. Pay upgrades initially use known-answer accuracy and substantive review.
- **[Faulty keys or small samples can misclassify workers]** -> Show sample counts, retain unknown/provisional assessments, surface widespread key failures for review, and support corrections, recalculation, and reinstatement.
- **[Local scoring rules can make global scores misleading]** -> Preserve scoped evidence and platform-owned global rules instead of averaging differently configured scores.
- **[Changing scores can make compensation unpredictable]** -> Freeze rates and bonus rules in funded offers; apply later changes to future work.

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
