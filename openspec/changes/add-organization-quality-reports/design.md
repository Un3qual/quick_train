## Context

See [proposal.md](proposal.md) for motivation and [the reporting spec](specs/organization-quality-reports/spec.md) for behavior. `add-worker-reputation` already plans private keys, a shared typed matcher and coherent exact-question diagnostics over native Task/QuestionResponse records. These reports extend that read path, not worker assessment or collection ownership. Reputation implementation remains unstarted.

## Goals / Non-Goals

**Goals:** Reuse native Ash queries and the diagnostic capture/matching boundary planned in `add-worker-reputation`, give organization applications bounded project summaries, and keep management inventory separate from answer-review authority.

**Non-Goals:** No new report resource, event stream, score, matcher, scheduling lifecycle or frontend. A manual reviewer-calibration practice does not require practice tables or production review actions. See the proposal for other scope exclusions.

## Decisions

### Extend existing scoped read actions

Use Ash read actions and typed GraphQL results in the owning project/reputation reporting paths. Reuse current authority helpers: `projects.manage` for explicit key-design reads; `tasks.review` for answer diagnostics. Authorize before protected capture and recheck current authority before returning results. Do not broaden general source policies to make the joins work. Native organization/project filtering and pinned-contract relationships supply the data; no direct Ecto boundary is justified.

Alternative considered: a separately persisted reporting domain. These values are derived on demand and need no independent lifecycle or ownership records.

### Capture one snapshot and reuse one matcher

Reuse reputation's short read-only `REPEATABLE READ` capture helper. Materialize the authorized pinned question contracts, current key revisions/enabled states, relevant lightweight submitted answer inputs and server cutoff on one connection, then close the transaction and run the existing typed matcher. No row locks, writes, lazy reads escaping capture or independent exact-report calls stitched into a project snapshot. Corrections committed later change the next request; reports neither publish assessments nor enqueue refreshes.

Use native filters/aggregates for inventory and grouping where they express the same contract. Inventory counts only successfully authored keys and their current enabled/disabled states; unsupported authoring requests create no inventory entry or new retained unsupported-key state. Keep known-answer comparison in the shared matcher rather than duplicate it in SQL. Produce evaluated/correct/incorrect counts and canonical categorical pairs from the same graded inputs. Return each question group's captured exact task/question/input/key identities, revision identities and enabled states alongside its totals, including disabled keys that contributed no evaluated answers. These are references to retained key revisions, not another report resource. A later drilldown is another request with its own revision/cutoff, not historical snapshot replay.

Alternative considered: reuse completed worker grades. Their cutoffs, settings and eligibility repairs may differ and their EWMA weights do not describe the all-history question sample.

### Keep categories comparable and output bounded

Group by the pinned published question identity within one project. Boolean values and static single-choice canonical option identities provide the initial distributions and reference/submitted pairs; task-input choices retain counts and exact diagnostics without a misleading cross-input categorical grouping. Return explicit availability for other families instead of implementing speculative geometry or semantic classifiers.

Select a bounded question page, then capture the complete relevant evidence for those groups, so page limits do not truncate their denominators. Paginate categorical pairs and key-revision references after counting the full question sample; provenance pages identify the total reference count and whether the returned list is complete. A later provenance page repeats its own coherently captured group totals and cutoff rather than imply it completes an older snapshot after a key change. Use stable question/answer/key identities for deterministic ordering; do not keep snapshots alive across page requests. Inventory totals come from native aggregates. Measure queries, returned rows/bytes and matching time for large projects before considering an additional optimization; pagination bounds output, not the work required for exact counts within a selected group.

Alternative considered: an exhaustive matrix or generic diagnostics framework for every answer family. Sparse canonical pair counts cover the approved categorical need and reuse existing diagnostics for the rest.

### Treat reports and reviewer practice as investigation tools

Counts describe authored references or submitted results against references, with denominators and availability. They cannot determine whether the reference, instructions or worker is responsible for a mismatch. A manager repairs a key through the existing action; a reviewer makes an actual production decision through the existing review action. Reading a report causes neither action.

[Reviewer calibration](../../future-features.md#reviewer-calibration-and-consistent-acceptance-criteria) starts outside the application: independent practice judgments, comparison and clarified acceptance guidance. No practice judgment becomes production review evidence. A dedicated workflow, if needed later, belongs to its own review change.

Alternative considered: automatic key invalidation or reviewer grading based on majority disagreement. Disagreement identifies something to investigate and does not establish a trusted answer or reviewer competence.

## Risks / Trade-offs

- Misreading balanced checks or aggregate project results as evidence for every worker → identify the authored-check versus evaluated-answer unit; preserve reputation's actual per-worker evidence requirements.
- A mistaken reference creates many mismatches → label results as comparisons against the supplied key and retain authorized diagnostic/repair paths; never change the key automatically.
- Large question groups can make exact on-demand matching expensive → capture lightweight inputs, bound groups/output, use native aggregates where equivalent and measure representative workloads before adding caching.
- Concurrent key changes or authorization revocation → coherent capture, explicit cutoff/revision provenance and current scoped authority checks; a newer drilldown reports its own snapshot.

## Migration Plan

Implement after the required key/matcher/diagnostic paths from `add-worker-reputation` exist. No new report tables or backfill are planned. Add scoped backend read actions and GraphQL results with focused behavior/performance checks, then run `mise run verify`. Rollback removes the additive report operations without changing keys, worker assessments or source work. Planning completion does not authorize runtime implementation.
