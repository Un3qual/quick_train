## Why

Organizations need to distinguish demonstrated correctness from agreement and experience when reviewing workers and deciding who receives future work. This change gives the approved reputation system its own specifications and implementation plan, replacing its detailed treatment in `record-future-product-architecture`.

## What Changes

- Add explainable project, organization, and platform-controlled global assessments with separate quality signals, evidence counts, history windows, and refresh status.
- Support private known-answer questions in ordinary work, retained key corrections, and organization reports of worker accuracy and question quality. Distribution remains best-effort.
- Detect repeated peer disagreement conservatively, with known-answer grading taking precedence and unfinished comparisons available only to reviewers.
- Freeze organization defaults and project overrides at activation. Keep weights application-owned and evidence availability explicit.
- Let signals inform reviewers or, when configured, restrict future project work. Preserve issued work, support attributable reinstatement, and keep completed access decisions effective during recalculation.
- Integrate reputation into fetch and direct assignment, including an initial calculation when needed. Permit workers to earn project-local history and support entry based on established organization/global evidence.
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
- Worker-facing reputation explanations and dispute workflows are deferred to [future features](../../future-features.md#worker-explanations-and-disputes). Organization reviewer evidence, key correction, and reinstatement remain in scope.
- Guaranteed per-worker test distribution, qualification tests, and the future question-authoring capabilities in [future-features.md](../../future-features.md). Qualification/requalification has its own intentionally incomplete [discussion skeleton](../add-qualification-tests/proposal.md); question-level scoring controls will require a coordinated reputation follow-up.

## Capabilities

### New Capabilities

- `worker-reputation`: scoped assessments, private known-answer evidence, conservative peer comparisons, explainable reviewer information, recoverable project restrictions, and recalculation.

### Modified Capabilities

- `projects`: authorize scoped reputation configuration, validate feasible project-local evidence minima, and freeze effective organization defaults/project overrides at activation while permitting explicit key correction and reinstatement after activation.
- `task-allocation`: apply reputation admission only to new issuance, preserving both allocation paths, durable retries, and existing-attempt authorization.

## Impact

- Adds a backend product domain `QuickTrain.Reputation` with Ash resources/actions, additive AshPostgres migrations, scoped GraphQL operations, and responsibility-specific recalculation work. Accounts, organization membership, authorization foundations, and existing typed response resources remain authoritative.
- Extends Projects activation/configuration and Tasks allocation; consumes existing attempt, response, and human-review evidence without replacing those ownership boundaries.
- Uses the implemented core collection specs as its baseline. It does not depend on the deferred `add-project-task-media` change or on Finance.
- Existing active projects retain their collection contract without silently acquiring reputation restrictions. The design's migration section governs opt-in behavior for newly activated projects.
- The [remaining implementation decisions](design.md#decisions-to-finalize-before-implementation) must be resolved before runtime work. Global reputation, preliminary peer reports, and both time-based and count-only windows remain in scope.
- The broader architecture record retains a concise link to this change instead of a second detailed reputation plan.
