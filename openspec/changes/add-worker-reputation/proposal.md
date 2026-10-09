## Why

Organizations need to distinguish demonstrated correctness from agreement and experience when reviewing workers and deciding who receives future work. This change gives the approved reputation system its own specifications and implementation plan, replacing its detailed treatment in `record-future-product-architecture`.

## What Changes

- Add explainable project, organization and platform-controlled global assessments, separating answer quality, completion reliability and submitted-question experience. Pool authoritative source evidence under each scope's own settings and history window rather than average narrower scores.
- Support private known-answer questions authored in draft work, exact typed matching, retained key correction/disabling/re-enabling and authorized retries. Freeze check designations at activation and preserve referenced key history during draft task removal. Distribution remains best-effort.
- Detect repeated peer disagreement conservatively using completed tasks, distinct submitted peers, target-dependent coverage and strict-majority consensus. Known-answer grading takes precedence. Disabled source-project agreement remains excluded in every scope; reviewer-only signals cannot indirectly restrict access.
- Treat substantive human review as optional supplementary worker evidence without review quotas, implicit approval of unreviewed answers or inheritance from a pooled project sample.
- Capture structured worker return reasons and separate comments, with authorized append-only excused/unexcused/awaiting-review classifications. Keep legitimate and unresolved returns visible but neutral; derive reliability from eligible outcomes using their original dates.
- Resolve typed organization defaults and draft overrides at activation, with application-owned weights and precise threshold comparisons. Validate automatic evidence requirements against history limits, peer capacity and finite authored per-worker maxima; advise on reviewer-only limits. The specs own numerical defaults and worked examples.
- Evaluate new fetch/direct assignment against the latest completed required assessments, preserving issued work and usable completed inputs during refresh. Support local initial evidence, broader entry requirements and attributable reinstatement with guarded retries. Earlier denials remain history rather than an admission latch.
- Provide scoped worker reports, paginated grouped concerns/detail and on-demand exact-question quality diagnostics under one captured key revision. Keep worker-assessment refresh metadata separate from uncached question reports.
- Reuse `projects.manage` for settings/key management and reinstatement, and `tasks.review` for reports/supporting evidence and return decisions. Require current organization authority, preserve worker/key privacy, and disclose only bounded global summaries for qualifying work relationships.
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
- Reputation email/webhook notifications, acknowledgment/dismissal/escalation workflows, and a separate concern lifecycle; organization applications consume the scoped backend queries.
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
- The [technical design pass](design.md#technical-design-pass-approved) is complete, approved and reconciled: current records with immutable calculations/history, captured-input guards and non-regressing publication, the existing allocation worker mutex with compatible lock mode and parent-reference initialization, hybrid Ash snapshot filtering/aggregation with initial Elixir matching/scoring, transactional Oban refresh scheduling, atomic admission history, and native storage integrity rules. The change is [ready for implementation](design.md#implementation-readiness); runtime concurrency, privacy, migration and performance verification remain required. All implementation tasks remain unchecked, and this documentation approval does not start runtime work. Global reputation, preliminary peer reports, and both time-based and count-only windows remain in scope.
- The broader architecture record retains a concise link to this change instead of a second detailed reputation plan.
