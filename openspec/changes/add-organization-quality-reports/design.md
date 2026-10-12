## Context

See [proposal.md](proposal.md) for motivation and [the reporting spec](specs/organization-quality-reports/spec.md) for behavior. `add-worker-reputation` already plans private keys, a shared typed matcher and coherent exact-question diagnostics over native Task/QuestionResponse records. These reports extend that read path, not worker assessment or collection ownership. Reputation implementation remains unstarted.

## Goals / Non-Goals

**Goals:** Reuse native Ash queries and the diagnostic capture/matching boundary planned in `add-worker-reputation`, give organization applications bounded project summaries, and keep management inventory separate from answer-review authority.

**Non-Goals:** No new report resource, event stream, score, matcher, scheduling lifecycle or frontend. A manual reviewer-calibration practice does not require practice tables or production review actions. See the proposal for other scope exclusions.

## Decisions

### Extend existing scoped read actions

Use Ash read actions and typed GraphQL results in the owning project/reputation reporting paths. Reuse current authority helpers: `projects.manage` for explicit key-design reads; `tasks.review` for answer diagnostics. Authorize before protected capture. Once the evidence transaction closes, perform a fresh current-authority check through Ash outside that snapshot before returning protected results. Rechecking inside `REPEATABLE READ` would miss a revocation committed after the snapshot began. Deny disclosure on lost authority or a failed check; this final authority read neither changes the captured evidence nor requires another evidence capture. Do not broaden general source policies to make the joins work. Native organization/project filtering and pinned-contract relationships supply the data; no direct Ecto boundary is justified.

Alternative considered: a separately persisted reporting domain. These values are derived on demand and need no independent lifecycle or ownership records.

### Capture one snapshot and reuse one matcher

Reuse reputation's read-only `REPEATABLE READ` capture/reduction helper and its [bounded answer processing](../add-worker-reputation/design.md#bounded-answer-processing). Capture the authorized pinned question contracts and server cutoff on one connection, then read relevant submitted answers and their effective keys in bounded pages. Run the existing typed matcher and reduce full-group counts/canonical pairs within that same snapshot, releasing page-local answer values and key loads before advancing. Close the transaction only after all source reads and reductions finish. No row locks, writes, complete answer materialization, lazy reads escaping capture or independent exact-report calls stitched into a project snapshot. Corrections committed later change the next request; reports neither publish assessments nor enqueue refreshes. A failed page returns no partial summary as a complete report.

Use native filters/aggregates for inventory and grouping where they express the same contract. Inventory counts only successfully authored keys and their current enabled/disabled states; unsupported authoring requests create no inventory entry or new retained unsupported-key state. Keep known-answer comparison in the shared matcher rather than duplicate it in SQL. Produce evaluated/correct/incorrect counts and canonical categorical pairs from the same graded inputs. Keep captured key identities/revisions/enabled states as calculation inputs, excluding disabled evaluations from the denominators. Return summary counts/rates with the pinned question identity, all-history diagnostic basis and capture cutoff. Inspect an individual exact task/question/input through the existing diagnostic drilldown, which returns its own captured key revision and enabled state. A later drilldown is another request with its own revision/cutoff, not historical snapshot replay.

Alternative considered: reuse completed worker grades. Their cutoffs, settings and eligibility repairs may differ and their EWMA weights do not describe the all-history question sample.

### Keep categories comparable and output bounded

Group by the pinned published question identity within one project. Boolean values and static single-choice canonical option identities provide the initial distributions and reference/submitted pairs; task-input choices retain counts and exact diagnostics without a misleading cross-input categorical grouping. Return explicit availability for other families instead of implementing speculative geometry or semantic classifiers.

Select a bounded question page, then scan all relevant evidence for those groups in bounded answer pages within its single read snapshot, so neither page limit truncates their denominators. Paginate categorical pairs after counting the full question sample. Pair counters retain compact canonical identities/counts rather than submitted answer populations; their size is a separate reporting cost. Add no key-reference manifest, provenance pagination or revision-set fingerprint. Summary cutoff and individual exact diagnostics meet the initial investigation need; a full historical manifest/replay requires a concrete later auditing requirement. Use stable question/answer identities for deterministic ordering; do not keep snapshots alive across separate report page requests. Inventory totals come from native aggregates. Measure query count/time, returned rows/bytes, matching time, snapshot/connection duration and peak loaded answers for large projects before considering an additional optimization; bounded answer pages reduce materialization without limiting the work required for exact full-group counts.

Alternative considered: an exhaustive matrix or generic diagnostics framework for every answer family. Sparse canonical pair counts cover the approved categorical need and reuse existing diagnostics for the rest.

### Treat reports and reviewer practice as investigation tools

Counts describe authored references or submitted results against references, with denominators and availability. They cannot determine whether the reference, instructions or worker is responsible for a mismatch. A manager repairs a key through the existing action; a reviewer makes an actual production decision through the existing review action. Reading a report causes neither action.

[Reviewer calibration](../../future-features.md#reviewer-calibration-and-consistent-acceptance-criteria) starts outside the application: independent practice judgments, comparison and clarified acceptance guidance. No practice judgment becomes production review evidence. A dedicated workflow, if needed later, belongs to its own review change.

Alternative considered: automatic key invalidation or reviewer grading based on majority disagreement. Disagreement identifies something to investigate and does not establish a trusted answer or reviewer competence.

## Risks / Trade-offs

- Misreading balanced checks or aggregate project results as evidence for every worker → identify the authored-check versus evaluated-answer unit; preserve reputation's actual per-worker evidence requirements.
- A mistaken reference creates many mismatches → label results as comparisons against the supplied key and retain authorized diagnostic/repair paths; never change the key automatically.
- Large question groups can make exact on-demand matching expensive → capture lightweight inputs, bound groups/output, use native aggregates where equivalent and measure representative workloads before adding caching.
- Concurrent key changes or authorization revocation → coherent capture, explicit summary cutoff, captured key revision on exact drilldown and current scoped authority checks; a newer drilldown reports its own snapshot.

## Migration Plan

Implement after the required key/matcher/diagnostic paths from `add-worker-reputation` exist. No new report tables or backfill are planned. Add scoped backend read actions and GraphQL results with focused behavior/performance checks, then run `mise run verify`. Rollback removes the additive report operations without changing keys, worker assessments or source work. Planning completion does not authorize runtime implementation.
