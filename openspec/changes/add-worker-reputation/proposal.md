## Why

Organizations need to distinguish demonstrated correctness from agreement and experience when reviewing workers and deciding who receives future work. This change gives the approved reputation system its own specifications and implementation plan, replacing its detailed treatment in `record-future-product-architecture`.

## What Changes

- Add explainable, rebuildable project, organization, and platform-controlled global assessments for the existing global User, retaining signal counts, provenance, evidence windows, and an unknown/provisional state for insufficient history.
- Let organizations author hidden known-answer checks for exact task/question/input contracts, with typed matching, retained key history, corrections, and recalculation.
- Detect repeated disagreement with sufficiently large, strongly agreeing groups of distinct peers; exclude the worker's own vote, ambiguous comparisons, and randomized display labels.
- Resolve organization defaults and project overrides into a frozen configuration at activation. Keep one application-owned calculation with bounded typed settings.
- Let each signal inform authorized reviewers or suspend new project work. Default disagreement to reviewer information; permit automatic enforcement only by explicit project opt-in. Preserve issued attempts and support correction and reinstatement.
- Integrate the same new-work check into fetch and direct assignment, including concurrency and allocation retries, without changing submission targets, answer acceptance, or collection results.
- Preserve the approved compensation direction in this change's design: optional pay bands and quality bonuses, strong quality evidence, and immutable funded offer terms. Implementing offers, reservations, settlement, or payouts belongs to a separate Finance change; reputation can ship independently.

Explicit non-goals:

- Implementing runtime behavior as part of the present documentation request; all implementation tasks remain unchecked.
- A separate worker account model, mandatory organization membership for external workers, a frontend, or platform-wide automatic bans.
- Canonical answer synthesis, automatic rejection based on disagreement, replacement demand, or changes to immutable worker responses and sealed exports.
- Customer-authored formulas, generic policy/version engines, duplicate reputation-event streams, or arbitrary score adjustments.
- Semantic free-text or spatial grading, media execution, or a Finance/payment-provider implementation.

## Capabilities

### New Capabilities

- `worker-reputation`: scoped assessments, private known-answer evidence, conservative peer comparisons, explainable reviewer information, recoverable project restrictions, and recalculation.

### Modified Capabilities

- `projects`: authorize scoped reputation configuration and freeze effective organization defaults/project overrides at activation while permitting explicit key correction and reinstatement after activation.
- `task-allocation`: apply reputation admission only to new issuance, preserving both allocation paths, durable retries, and existing-attempt authorization.

## Impact

- Adds a backend product domain `QuickTrain.Reputation` with Ash resources/actions, additive AshPostgres migrations, scoped GraphQL operations, and responsibility-specific recalculation work. Accounts, organization membership, authorization foundations, and existing typed response resources remain authoritative.
- Extends Projects activation/configuration and Tasks allocation; consumes existing attempt, response, and human-review evidence without replacing those ownership boundaries.
- Uses the implemented core collection specs as its baseline. It does not depend on the deferred `add-project-task-media` change or on Finance.
- Existing active projects retain their collection contract without silently acquiring reputation restrictions. The design's migration section governs opt-in behavior for newly activated projects.
- Exact scoring arithmetic, numerical defaults, cold-start admission, and recovery/freshness details were not settled in the approved discussion. They are explicit pre-implementation decisions in this change's design and first task, not invented defaults or claims of implemented behavior.
- The broader architecture record retains a concise link to this change instead of a second detailed reputation plan.
