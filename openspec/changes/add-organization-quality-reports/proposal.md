## Why

Organizations need to see whether their known-answer checks cover the questions they are collecting and what errors appear against those references. Worker reputation and its planned exact-question diagnostics will provide the underlying evidence, but do not explain project check design or recurring answer confusions.

## What Changes

- Add project check-design summaries: check counts per pinned question, questions without checks, disabled checks, and expected-answer distributions for comparable boolean and static single-choice questions. Count only successfully authored keys; unsupported key requests remain authoring validation failures. These are advisory counts of authored checks, not guaranteed delivery to every worker.
- Add project question-quality summaries and categorical reference-versus-submitted answer counts, with captured key-revision provenance per question group and drilldown to the planned exact task/question/input diagnostics. Show denominators and unavailable results explicitly so a low-volume question or faulty reference is not mistaken for proven worker failure.
- Reuse organization-scoped backend queries, private key permissions, the shared typed matcher and coherent on-demand report snapshots. Reports do not change keys, scores, access, pay, submitted answers or project state.

Explicit non-goals: runtime implementation during this planning request; a frontend; an overall project quality score; automatic balancing, pauses or worker penalties; guaranteed per-worker checks; a second grading engine; stored report projections or refresh jobs; spatial/semantic error analysis; reviewer ratings or weighted voting. Reviewer calibration starts as a [manual practice](../../future-features.md#reviewer-calibration-and-consistent-acceptance-criteria), with a dedicated workflow deferred. Informational worker task/project counts remain in [worker reputation](../add-worker-reputation/proposal.md).

## Capabilities

### New Capabilities

- `organization-quality-reports`: private project check-design summaries, categorical error patterns, coherent diagnostic snapshots and read-only scoped reporting.

### Modified Capabilities

None. This change extends reporting alongside the planned worker-reputation capability without changing its grading, key lifecycle, assessment or admission requirements.

## Impact

- Depends on the known-answer authoring, typed comparison and exact-question diagnostics planned in `add-worker-reputation`; reputation can ship independently.
- Extends Ash read actions and scoped GraphQL results over Projects, Tasks, pinned Forms and private keys/answers. Reuses `projects.manage` for check-design inventory and `tasks.review` for submitted-answer diagnostics, without granting general source browsing or cross-organization access.
- Preserves the backend-template boundary: no frontend, Finance integration or new worker account model. No dependency upgrade or new persistent report resource is planned.
- All implementation tasks remain unchecked. Development and behavior verification belong to the later apply phase.
