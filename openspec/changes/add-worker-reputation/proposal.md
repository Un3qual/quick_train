## Why

Organizations need to distinguish demonstrated correctness from agreement and experience when reviewing workers and deciding who receives future work. This change gives the approved reputation system its own specifications and implementation plan, replacing its detailed treatment in `record-future-product-architecture`.

## What Changes

- Add explainable project, organization and platform-controlled global assessments that separate answer quality, completion reliability and submitted-question experience. Report lifetime and observation-based EWMA performance with evidence counts, task/project coverage, original dates and freshness under the [reputation contract](specs/worker-reputation/spec.md).
- Support private known-answer checks authored in draft work, typed matching and retained key corrections/disabling/re-enabling. Keep distribution best-effort and give known-answer grading precedence over peer agreement under the [key lifecycle](specs/worker-reputation/spec.md#requirement-known-answer-authoring-respects-the-project-lifecycle).
- Detect repeated peer disagreement conservatively from completed comparable work. Allow published question contracts to exclude subjective questions, preserve independent scope settings, and leave human review as optional supplementary evidence; see [peer comparison](specs/worker-reputation/spec.md#requirement-peer-comparison-requires-sufficient-comparable-evidence) and [question authoring](specs/versioned-forms/spec.md).
- Capture worker return reasons and reviewer classifications. Keep returns and expirations visible but neutral until an eligible outcome is confirmed unexcused under the [reliability contract](specs/worker-reputation/spec.md#requirement-reliability-includes-unexcused-returns-and-excludes-legitimate-returns).
- Resolve organization defaults and draft-project overrides into frozen, feasible [project settings](specs/projects/spec.md). Keep contributor weights application-owned, default to informing reviewers, and require explicit opt-in for automatic access rules.
- Apply reputation rules only to new work using completed assessments, preserving issued work and usable inputs during refresh. Support local initial evidence, broader-history entry rules, retained access decisions and recoverable restrictions through [admission and reinstatement](design.md#allocation-and-retained-decisions).
- Provide scoped worker reports, grouped concerns and return/expiration classification views, plus on-demand known-answer diagnostics and low reference-match warnings. Preserve historical evidence and distinguish current rule effects from historical scores through the [reviewer read paths](design.md#reviewer-read-paths). Support rare global-only source repair through [private operator maintenance](specs/worker-reputation/spec.md#requirement-faulty-source-evidence-has-a-global-only-remedy).
- Enforce global staff/worker separation with one shared `NotStaff` check while preserving ordinary internal membership and retained work ownership. Reuse scoped management/review capabilities and protect current, historical and nested global disclosure through the [authorization contracts](specs/worker-reputation/spec.md#requirement-reputation-operations-fail-closed-within-organization-scope).
- Keep calculations coherent and bounded, batch affected worker refreshes, and avoid refresh work when inputs have not changed. The [calculation design](design.md#capture-and-publication), [scheduling protocol](design.md#scheduling-and-verification-boundary) and [peer discovery](design.md#deferred-peer-discovery-coverage) own the implementation details; the [verification boundary](design.md#scheduling-and-verification-boundary) covers correctness, concurrency and performance.
- Retain optional pay bands and quality bonuses as a [future Finance integration contract](design.md#6-keep-compensation-commitments-in-finance); reputation ships independently.

The specs define [reputation behavior](specs/worker-reputation/spec.md), [project configuration](specs/projects/spec.md), [question authoring](specs/versioned-forms/spec.md), and [allocation](specs/task-allocation/spec.md). The [design](design.md) owns implementation choices and rationale; the [tasks](tasks.md) track delivery and verification.

Explicit non-goals:

- Implementing runtime behavior as part of the present documentation request; all implementation tasks remain unchecked.
- A separate worker account model, mandatory organization membership for external workers, a frontend, or platform-wide automatic reputation bans.
- Canonical answer synthesis, automatic rejection based on disagreement, replacement demand, or changes to immutable worker responses and sealed exports.
- Customer-authored formulas, generic policy/version engines, duplicate reputation-event streams, or arbitrary score adjustments. Hard count/time windows, elapsed-time decay and multiple overlapping weighted periods are outside the selected lifetime/EWMA model.
- Key-exposure tracking, special key-reveal actions, and reputation exclusions or key-edit prohibitions based solely on an authorized user's prior knowledge of a key.
- Incremental reputation extension, unchanged-metric reuse, saved-prefix metadata and optimization-specific coverage/base-publication machinery; see [incremental work](../../future-features.md#incremental-reputation-calculation) and [metric reuse](../../future-features.md#reuse-of-unchanged-reputation-metrics).
- Customer-adjustable organization/project score weights; these are recorded as [future work](../../future-features.md#organization-and-project-score-weights).
- Semantic free-text or spatial grading, media execution, or a Finance/payment-provider implementation.
- Automated review sampling, review-budget management, correction-similarity grades, or a new selective-review lifecycle. Record [review sampling](../../future-features.md#review-sampling-and-budgets), [original-versus-corrected quality](../../future-features.md#quality-of-original-answers-after-reviewer-correction), and [spatial grading](../../future-features.md#spatial-grading-for-bounding-boxes-and-segmentation) as future capabilities; this change consumes existing review facts and supported grading outcomes.
- Worker-facing reputation explanations and dispute workflows are deferred to [future features](../../future-features.md#worker-explanations-and-disputes). Organization reviewer evidence, key correction, and reinstatement remain in scope.
- Reputation email/webhook notifications, acknowledgment/dismissal/escalation workflows, and a separate concern lifecycle; organization applications consume the scoped backend queries.
- Project check-design summaries and categorical error-pattern reports belong to the separate [organization quality-reporting change](../add-organization-quality-reports/proposal.md). [Reviewer calibration](../../future-features.md#reviewer-calibration-and-consistent-acceptance-criteria) starts as a manual practice; a dedicated practice workflow remains future work.
- Guaranteed per-worker test distribution, qualification tests, and broader future question-authoring/scoring capabilities in [future-features.md](../../future-features.md). Qualification/requalification has its own intentionally incomplete [discussion skeleton](../add-qualification-tests/proposal.md). Only the simple question-level peer-participation boolean is brought into this change; other question-level signal controls and adjustable weights remain deferred.

## Capabilities

### New Capabilities

- `worker-reputation`: scoped assessments, private known-answer evidence, conservative peer comparisons, explainable reviewer information, recoverable project restrictions, and recalculation.

### Modified Capabilities

- `versioned-forms`: authorize one draft-question peer-participation boolean through existing Forms permissions, preserve it during copying, and freeze it at publication.
- `projects`: authorize scoped reputation configuration, validate feasible project-local evidence minima, and freeze effective organization defaults/project overrides at activation while permitting key correction, explicit disabling/re-enabling of existing keys, return classification/correction, and reinstatement after activation.
- `task-allocation`: apply reputation admission only to new issuance, preserving both allocation paths, durable retries, and existing-attempt authorization; capture return reasons through ordinary release without waiting for classification.

## Impact

- Adds a backend product domain `QuickTrain.Reputation` with Ash resources/actions, additive AshPostgres migrations, scoped GraphQL operations, and responsibility-specific recalculation work. Accounts, organization membership, authorization foundations, and existing typed response resources remain authoritative.
- Extends Forms question authoring, Projects activation/configuration and Tasks allocation; consumes native participation, response and explicit human-review evidence without replacing those ownership boundaries. The approved [collection simplifications](../simplify-work-participation-and-processing/proposal.md) own their native lifecycle changes and precede reputation integration.
- Uses the implemented core collection specs as its baseline. It layers onto `simplify-work-participation-and-processing`, not the deferred `add-project-task-media` change or Finance.
- QuickTrain is unreleased under the root [release-status instructions](../../../AGENTS.md#release-status). Implement the current contract directly, with no legacy-project configuration, historical-data backfill or production rollout/rollback workflow. Ordinary schema setup and runtime frozen-contract/history protections remain in scope.
- The [approved technical design](design.md#technical-design-pass-approved) owns the implementation protocols, and [readiness](design.md#implementation-readiness) records the outstanding verification work. All implementation tasks remain unchecked; planning approval does not start runtime work.
- The broader architecture record retains a concise link to this change instead of a second detailed reputation plan.
