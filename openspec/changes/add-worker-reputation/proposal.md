## Why

Organizations need to distinguish demonstrated correctness from agreement and experience when reviewing workers and deciding who receives future work. This change gives the approved reputation system its own specifications and implementation plan, replacing its detailed treatment in `record-future-product-architecture`.

## What Changes

- Add explainable project, organization, and platform-controlled global assessments with an answer-quality score from known-answer correctness, substantive human review, and peer agreement; separate completion reliability; and experience counts without a quality-score weight. Preserve evidence counts, time-based or per-signal count-based history windows, and refresh status.
- Support private known-answer questions in ordinary work, retained key corrections and explicit disabling/re-enabling, and organization reports of worker accuracy within configured windows and question quality across all evaluable answers to each exact task/question. Distribution remains best-effort.
- Detect repeated peer disagreement conservatively, with known-answer grading taking precedence and unfinished comparisons available only to reviewers.
- Treat human review as supplementary evidence, excluded from organization/project default quality scoring unless explicitly selected. Preserve actual review decisions and counts without requiring per-worker review quotas or assigning a project sample's quality to unreviewed workers. For subjective work, assess instruction compliance rather than conformity of opinions.
- Use the approved normalized weighted average and project defaults: 60/30/10 relative quality weights, 20/20/30 worker evidence minima, and the most recent 100 eligible observations per signal. Keep supporting observation dates visible and retain configurable time-based windows.
- Capture worker return reasons and let organization reviewers classify them as excused, unexcused, or awaiting review. Reliability uses completions divided by completions plus eligible expirations and unexcused returns; excused/unreviewed returns remain visible without lowering the score, and corrections repair derived results.
- Freeze organization defaults and project overrides at activation. Reject impossible automatic evidence requirements and advise on reviewer-only limits. Keep weights application-owned and evidence availability explicit.
- Let signals inform reviewers or, when configured, restrict future project work. Preserve issued work, support attributable reinstatement, and keep completed reputation inputs usable during recalculation.
- Evaluate each new fetch/direct assignment against the latest completed scoped reputation, including an initial calculation when needed. Retain earlier access outcomes as history without requiring a project refresh after broader reputation improves. Permit workers to earn project-local history and support entry based on established organization/global evidence.
- Retain optional pay bands and quality bonuses as a [future Finance integration contract](design.md#6-keep-compensation-commitments-in-finance); reputation ships independently.

The specs define [reputation behavior](specs/worker-reputation/spec.md), [project configuration](specs/projects/spec.md), and [allocation](specs/task-allocation/spec.md). The [design](design.md) owns implementation choices and rationale; the [tasks](tasks.md) track delivery and verification.

Explicit non-goals:

- Implementing runtime behavior as part of the present documentation request; all implementation tasks remain unchecked.
- A separate worker account model, mandatory organization membership for external workers, a frontend, or platform-wide automatic bans.
- Canonical answer synthesis, automatic rejection based on disagreement, replacement demand, or changes to immutable worker responses and sealed exports.
- Customer-authored formulas, generic policy/version engines, duplicate reputation-event streams, or arbitrary score adjustments.
- Key-exposure tracking, special key-reveal actions, and reputation exclusions or key-edit prohibitions based solely on an authorized user's prior knowledge of a key.
- Customer-adjustable organization/project score weights; these are recorded as [future work](../../future-features.md#organization-and-project-score-weights).
- Semantic free-text or spatial grading, media execution, or a Finance/payment-provider implementation.
- Automated review sampling, review-budget management, or a new selective-review lifecycle. Record [review sampling](../../future-features.md#review-sampling-and-budgets) and [spatial grading](../../future-features.md#spatial-grading-for-bounding-boxes-and-segmentation) as future capabilities; this change consumes existing review facts and supported grading outcomes.
- Worker-facing reputation explanations and dispute workflows are deferred to [future features](../../future-features.md#worker-explanations-and-disputes). Organization reviewer evidence, key correction, and reinstatement remain in scope.
- Guaranteed per-worker test distribution, qualification tests, and the future question-authoring capabilities in [future-features.md](../../future-features.md). Qualification/requalification has its own intentionally incomplete [discussion skeleton](../add-qualification-tests/proposal.md); question-level scoring controls will require a coordinated reputation follow-up.

## Capabilities

### New Capabilities

- `worker-reputation`: scoped assessments, private known-answer evidence, conservative peer comparisons, explainable reviewer information, recoverable project restrictions, and recalculation.

### Modified Capabilities

- `projects`: authorize scoped reputation configuration, validate feasible project-local evidence minima, and freeze effective organization defaults/project overrides at activation while permitting key correction, explicit disabling/re-enabling of existing keys, return classification/correction, and reinstatement after activation.
- `task-allocation`: apply reputation admission only to new issuance, preserving both allocation paths, durable retries, and existing-attempt authorization; capture return reasons through ordinary release without waiting for classification.

## Impact

- Adds a backend product domain `QuickTrain.Reputation` with Ash resources/actions, additive AshPostgres migrations, scoped GraphQL operations, and responsibility-specific recalculation work. Accounts, organization membership, authorization foundations, and existing typed response resources remain authoritative.
- Extends Projects activation/configuration and Tasks allocation; consumes existing attempt, response, and human-review evidence without replacing those ownership boundaries.
- Uses the implemented core collection specs as its baseline. It does not depend on the deferred `add-project-task-media` change or on Finance.
- Existing active projects retain their collection contract without silently acquiring reputation restrictions. The design's migration section governs opt-in behavior for newly activated projects.
- The [remaining implementation decisions](design.md#decisions-to-finalize-before-implementation) must be resolved before runtime work. Global reputation, preliminary peer reports, and both time-based and count-only windows remain in scope.
- The broader architecture record retains a concise link to this change instead of a second detailed reputation plan.
