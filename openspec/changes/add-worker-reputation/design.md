## Context

See [proposal.md](proposal.md) for scope. This change owns the reputation decisions approved on 2026-10-05 and previously placed in `record-future-product-architecture`. It is an implementation proposal, not evidence that reputation has shipped. The approved compensation direction is retained below as a future Finance integration contract.

Core collection already supplies immutable TaskInputs, submitted QuestionResponses, attempt provenance, append-only ReviewDecisions, frozen Projects, and sealed exports. `QuickTrain.Tasks.Reviews.QuestionReview.initial_decisions!/2` automatically accepts answered submissions, so acceptance alone is not correctness evidence. `QuickTrain.Tasks.Access.WorkerEligibility` currently serves both allocation and existing-attempt authorization; putting reputation restrictions directly into that shared filter would revoke work already issued. `AttemptAllocation` also replays allocation request keys before selecting new work. These are concrete integration boundaries for this change.

The [worker-reputation delta](specs/worker-reputation/spec.md) defines the new behavior; [projects](specs/projects/spec.md) and [task-allocation](specs/task-allocation/spec.md) extend the implemented collection contract. This change does not depend on media execution or Finance.

The specs own behavioral requirements and scenarios. This design records implementation choices, rationale, and unresolved decisions; the [tasks](tasks.md) link those contracts to delivery work.

## Goals / Non-Goals

**Goals:**

- Keep authoritative evidence in its owning domain and make assessments reproducible, scoped, and explainable.
- Implement known-answer checks and conservative peer comparison using existing immutable task identities and typed answers.
- Make project restrictions recoverable without coupling them to account bans, answer acceptance, or payment.
- Use Ash resources, actions, relationships, policies, constraints, and generators; use existing Oban infrastructure for recalculation where asynchronous work is appropriate.

**Non-Goals:**

Follow the [proposal's scope exclusions](proposal.md#what-changes). In particular, do not add a general policy engine, duplicate evidence stream, separate automatic-suspension projection, or speculative Finance adapter/plugin interface.

## Decisions

### 1. Separate evidence dimensions and assessment scope

Add `QuickTrain.Reputation` for derived assessments and their evaluation workflows. Use the existing global User and authoritative Attempts, QuestionResponses, skips, and ReviewDecisions. Preserve contribution provenance without copying source records into a parallel event store.

The [scoped-assessment contract](specs/worker-reputation/spec.md#requirement-scoped-assessments-preserve-evidence-and-uncertainty) defines separate metrics, the three evidence states, and independent refresh metadata. The [source-fact contract](specs/worker-reputation/spec.md#requirement-review-and-task-facts-retain-their-meaning) distinguishes substantive human review from automatic acceptance. Global calculations use platform rules instead of averaging incompatible local scores.

Alternative rejected: a single opaque reputation percentage or a global average of organization scores. Either would hide uncertainty and combine incompatible judgments.

### 2. Put known answers beside exact authored task contracts

A batch is represented by a Project and its authored Tasks, so no new Batch resource is needed. Bind typed keys to the [exact task/question/input contract](specs/worker-reputation/spec.md#requirement-known-answer-checks-bind-to-exact-task-evidence), using existing option/input identities and answer-family validation. List ranking, set/order semantics, and numeric boundary details explicitly before enabling those families; do not silently interpret arbitrary strings or geometry.

Use ordinary allocation and the [activation feasibility checks](specs/projects/spec.md#requirement-activation-identifies-impossible-project-local-evidence-settings). Shared task capacity can be exhausted before later workers encounter known-answer questions. This avoids a second allocator or increased task demand; guaranteed per-worker delivery requires separate scope and is not supplied by the unfinished [qualification skeleton](../add-qualification-tests/proposal.md).

Enforce [key privacy](specs/worker-reputation/spec.md#requirement-keys-and-check-designations-remain-private) through scoped management actions and worker-facing GraphQL boundaries, including form/task/attempt traversal and mutation results. A hidden flag on a generally readable resource is insufficient. Authorized staff who also work follow the ordinary rules; no key-knowledge tracking is needed.

Retain key/matching-rule history for [correction and repair](specs/worker-reputation/spec.md#requirement-key-corrections-preserve-history-and-repair-assessments), using existing deliberate-action and retry conventions. Build the two [organization reports](specs/worker-reputation/spec.md#requirement-organizations-can-inspect-known-answer-evidence-and-question-quality) as bounded read views over evaluation evidence. Use “known-answer evidence” and “question-quality reporting” in API descriptions, rather than unexplained “coverage” or “health” labels. A check is an expected-answer question within ordinary work; the reports add no worker interaction or separate test.

Alternative rejected: overwriting a key and losing the reason for earlier scores, or using a generic form-level answer key across different tasks.

### 3. Derive agreement only from comparable distinct peers

Group responses by exact task/question/pinned input contract and apply the [peer eligibility rules](specs/worker-reputation/spec.md#requirement-peer-comparison-requires-sufficient-comparable-evidence). Numeric comparison uses a robust center such as the median with explicit tolerance and concentration requirements; a median alone does not prove consensus.

Apply [known-answer precedence](specs/worker-reputation/spec.md#requirement-known-answer-grading-takes-precedence-over-peer-disagreement) before peer scoring to prevent double counting and contradictory penalties. Keep [unfinished comparisons](specs/worker-reputation/spec.md#requirement-unfinished-peer-comparisons-cannot-restrict-work) available as preliminary reviewer information without changing the existing submission target. A project with too few responses has no usable peer signal; the implementation must not create additional demand to manufacture one.

Alternative rejected: penalizing each deviation from the current plurality. The [repeated-disagreement contract](specs/worker-reputation/spec.md#requirement-repeated-disagreement-is-weaker-than-correctness) instead bounds influence below correctness and permits disabling agreement for subjective work.

### 4. Freeze a small typed configuration at activation

Resolve direct organization defaults and draft-project overrides under the activation transaction, following the [project configuration contract](specs/projects/spec.md#requirement-organization-defaults-resolve-into-explicit-project-reputation-settings). Default edits and activation must serialize or obtain a coherent snapshot so activation cannot mix configurations.

Implement the [evidence feasibility checks](specs/projects/spec.md#requirement-activation-identifies-impossible-project-local-evidence-settings) as direct comparisons against the applicable history bound, local submission target, or authored check count. Return scoped validation errors or reviewer-only advisories without adding an allocation simulation or automatically changing settings. Broader entry rules use their own scope's limits.

Keep weights in one named application-owned definition and pass the effective map explicitly into the shared calculation. Developers should be able to change weights and focused tests in one place; avoid coefficients scattered across handlers, reports, jobs, and admission checks, or a database column per weight. The [weight contract](specs/worker-reputation/spec.md#requirement-application-owned-weights-are-explicit-calculation-inputs) specifies retained values, frozen projects, and platform-weight recalculation. Numerical calibration remains unresolved.

Pass an explicit contributing-signal set into that same calculation for each result and retain the set with its provenance. Apply the [disabled/insufficient rules](specs/worker-reputation/spec.md#requirement-disabled-and-insufficient-signals-have-distinct-scoring-outcomes) to it. Filter organization/global per-signal inputs for project admission without changing their independent assessment or exposing private evidence. This implements [reviewer-only exclusion](specs/worker-reputation/spec.md#requirement-signal-actions-support-review-and-recoverable-project-suspension) without a separate scoring engine.

Use the existing assessment state and admission decision for the [initial-evidence path](specs/projects/spec.md#requirement-reputation-admission-provides-a-path-to-initial-project-evidence), rather than adding a qualification-attempt lifecycle. Requiring local history before any work would leave no way to earn it; established entry requirements instead use independently earned organization/global evidence.

Alternative rejected: making every setting global or exposing customer formulas. The bounded typed configuration gives organizations useful controls while keeping one application-owned algorithm; retained key history and calculation provenance do not require a generic policy/version hierarchy.

### 5. Add a new-work gate without changing ongoing authorization

Place the shared gate after account/organization/audience checks and committed allocation-retry resolution, before issuance. Preserve `WorkerEligibility` for existing-attempt authorization. Do not write `ProjectWorkerAccess` blocks for reputation: those blocks intentionally revoke ongoing access, unlike the [new-work-only contract](specs/task-allocation/spec.md#requirement-project-worker-eligibility-preserves-optional-membership).

Store metrics and automatic access reasons in one derived project/worker result, with manual reinstatement as a separate attributable input. Use conditional atomic publication under the [fixed-snapshot contract](specs/worker-reputation/spec.md#requirement-assessments-and-automatic-access-reasons-publish-together), rather than synchronizing a second suspension record. Retain captured source/supporting revisions, evaluation cutoff, effective settings, and reinstatement inputs. Distinguish ordinary appends and passed refresh boundaries from invalidating corrections/settings/reinstatement; snapshot ordering must not regress the published source frontier or cutoff. Concrete storage remains an implementation decision, not a reason to add a copied evidence stream.

Allocation reads the completed project decision with applicable reinstatement. It does not traverse supporting freshness or wait for jobs; the [pending-recalculation contract](specs/worker-reputation/spec.md#requirement-pending-recalculation-preserves-completed-access-decisions) owns the access behavior. Retain supporting as-of/pending metadata when using completed inputs that already await refresh.

Apply [reinstatement cutoffs](specs/worker-reputation/spec.md#requirement-reinstatement-evaluates-selected-rules-using-subsequent-evidence) through the shared history-selection/calculation boundary for selected local access rules. Keep historical reputation separate from that rule-specific evidence selection; reuse the existing windows, minima, and thresholds rather than adding recovery scores or timed exemptions.

Allocation currently locks Project, worker User, then task capacity. Choose compatible publication/reinstatement ordering, post-lock checks, and stable ordering for multi-worker recalculation. Submission/review callbacks already hold outcome/task locks and must not introduce inversions. The [atomic allocation contract](specs/task-allocation/spec.md#requirement-reputation-admission-is-atomic-and-shared-by-allocation-routes) defines the races and retry behavior.

Prepare missing initial project/supporting assessments before the allocation transaction and locks, after scoped authorization and committed-retry detection. Under the locks, revalidate authority, project configuration, request key, completed decision, and reinstatement; prefer a concurrent completed result or conditionally publish the candidate. If invalidated and no completed decision exists, release locks before re-preparing within the request. The [first-access contract](specs/worker-reputation/spec.md#requirement-first-access-does-not-depend-on-a-queued-initial-calculation) specifies supporting-input reuse and avoids a queued warm-up lifecycle.

Keep history selection behind one small function accepting a window description and evaluation cutoff and returning observations plus any next time-dependent invalidation. The shared scorer receives those observations explicitly; it neither queries time nor filters its own window. Both time-based and count-only windows remain in scope. Apply the [time-window contract](specs/worker-reputation/spec.md#requirement-time-windows-expire-evidence-without-requiring-a-new-submission) for original event ages, cutoffs, scheduled refresh, and missed-boundary detection. Count-only windows have no clock-driven expiration and use deterministic original-event order. Recalculation/publication consumes the returned freshness facts; admission stays independent of window type.

Use independent database connections and deliberate barriers for the concurrency checks in [tasks 4 and 5](tasks.md#4-recalculate-and-support-reviewer-recovery), including stale/corrected publication, activation races, and committed-retry recovery.

Alternative rejected: pausing work until jobs finish, expiring a grace period into a pause, cancelling in-flight work, or reusing revoking audience blocks. Refresh delay remains visible while completed decisions govern access.

### 6. Keep compensation commitments in Finance

Optional reputation-based pay bands and quality bonuses are approved. Organizations provide defaults and projects may override them; the future Finance activation contract resolves and freezes rate rules. A project can offer a standard rate and higher rates for sufficiently established project- or organization-scoped quality. Initial upgrades use known-answer correctness and substantive human review with minimum evidence. Peer agreement remains a monitoring and eligibility signal until its suitability for compensation has been established for that project. Competitor rates and thresholds are not QuickTrain defaults.

Historical reputation selects the rate for a future offer. A quality bonus evaluates performance on the offered work using criteria disclosed with that offer. Eligibility for better-paid projects is another use of reputation and does not imply a different price for identical work. Admission, answer acceptance, and monetary settlement are separate decisions.

Finance must show and freeze the quoted rate and bonus criteria when work is offered/fetched, with enough evidence to explain the selected band. It must reserve the maximum organization charge, including any promised conditional bonus, atomically with issuance. Later score/configuration changes affect future offers and cannot alter an issued offer's quoted rate or bonus rules. Skips, rejections, and partial answers remain task facts; the pinned rate terms determine payment treatment.

Reputation supplies scoped evidence and calculation provenance. Finance owns WorkOffers, funding reservations, settlement, ledger accounting, and payouts. This change adds no paid-offer or bonus tables and does not require a Finance implementation to complete. The future Finance change must restate these terms as behavioral specs and test rate changes, conditional bonus settlement, reservation failure, and offer/reputation races against the implemented reputation API.

Alternative rejected: retroactive rate reductions or adding a payment subsystem to make reputation useful. Frozen offers keep commitments predictable and let reputation ship independently.

### 7. Use scoped Ash operations and additive storage

Generate the Reputation domain/resources and migrations with the installed Ash tooling, then tailor them to the approved scope. Keep settings, keys/history, assessments containing automatic access reasons, and manual reinstatement records distinct only where their lifecycles or authorization require it; do not create an additional automatic-suspension projection or generic policy-resource family. Use Ash UUID identities, explicit organization/project references, database constraints, and native actions/domain interfaces. No direct-Ecto exception is proposed.

Reuse the organization-capability path for management and review operations with explicit grants and fail-closed scope. Preserve external worker access through existing audience/attempt authority. Expose deliberate bounded GraphQL reads and mutations; authoring authority does not imply general read access. Do not expose global raw evidence or let a local setting change platform-owned calculations. Exact capability names and global-summary disclosure must be fixed in the implementation contract.

The explanations delivered by this change are for authorized organization reviewers. Detailed worker-facing reputation explanations and worker-initiated disputes are deferred. Workers still receive ordinary work-access outcomes; this does not add a personal evidence breakdown or an appeal action. Organization reviewers retain evidence inspection, key correction, and reinstatement without depending on a future dispute workflow.

Use responsibility-specific Oban jobs for affected-scope recalculation and repair. Keep small source changes transactional with their invalidation/scheduling facts; repeated delivery must converge. Prefer rebuilding from source facts over incremental counters that cannot be reconciled.

### Future question capabilities

[Multiple acceptable known answers and question-level scoring controls](../../future-features.md) are recorded outside this change. Acceptable-answer sets belong to question/key authoring and grading; reputation will consume their grading outcome when implemented.

Question-level controls are approved future work requiring a published-question contract change. That work must also modify reputation's question selection, denominators and minimum-evidence counts, scoring and enforcement eligibility, explanations, and rebuild behavior. Resolve the controls through the pinned question version and effective project configuration, preserving already-active contracts. This release retains project-level settings; for a form mixing factual and subjective questions, disable agreement scoring/enforcement for the whole project until selective controls exist rather than treating every question as objective. No question schema or extra override hierarchy is introduced here.

## Research Rationale

These first-party sources were reviewed during the approved discussion on 2026-10-05. This change relocates that research; competitor numerical thresholds, permanent exclusions, and commercial terms are not QuickTrain requirements.

- [Appen Quality Flow](https://success.appen.com/appen-success-center/settings/guide-to-test-questions-in-quality-flow) links known-answer accuracy with job access and repairs scores/access after faulty-key corrections. Its [test-question guidance](https://success.appen.com/appen-success-center/settings/guide-to-test-questions-in-quality-flow/test-question-best-practices) also describes job pausing for widespread misses/contests. This supports recoverable enforcement and key-quality inspection; automatic project pausing is not adopted here.
- [Toloka Quorum](https://platform.toloka.ai/docs/reference/nodes/quorum/) demonstrates exclusion from future work for repeated disagreement separately from grading existing answers. [MTurk eligibility](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMechanicalTurkRequester/SelectingEligibleWorkers.html) and [consensus policies](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMturkAPI/ApiReference_HITReviewPolicies.html) separate access requirements from optional scoring actions and exclude inconclusive questions from agreement scores.
- [Labelbox's quality strategy](https://labelbox.com/guides/how-to-create-a-quality-strategy-for-your-data-labeling-project/) emphasizes investigation, feedback, and retraining and distinguishes subjective agreement from accuracy. [Prolific's quality controls](https://researcher-help.prolific.com/en/articles/445223-bulk-rejecting-exceptionally-fast-submissions) illustrate reviewer information with optional automation. These support conservative disagreement defaults.
- [Toloka's marketplace pricing documentation](https://github.com/Toloka/docs/blob/main/en/guide/concepts/dynamic-pricing.md) describes skill-dependent bands fixed at assignment. This is an older marketplace precedent; availability in its newer node platform was not confirmed. [MTurk bonuses](https://docs.aws.amazon.com/AWSMechTurk/latest/AWSMechanicalTurkRequester/IntroCoreConcepts.html) and [Prolific performance payments](https://researcher-help.prolific.com/en/articles/445234-can-i-make-partial-payments-to-participants) support base pay plus performance bonuses. [Remotasks](https://www.remotasks.com/en/projects/90551) describes quality unlocking better-paid tasks. [Outlier](https://outlier.ai/) advertises quality-based rewards without a precise public historical-score-to-rate formula in the reviewed pages. These are different mechanisms, not one universal reputation multiplier.

## Risks / Trade-offs

- **[Majority agreement can reward conformity]** → Exclude ambiguous comparisons, require sufficient distinct peers and worker history, bound agreement below correctness, and default enforcement to reviewer information.
- **[Faulty keys or small samples misclassify workers]** → Preserve insufficient-evidence states, counts, key history, broad-failure evidence, and correction/reinstatement workflows.
- **[Workers encounter too few known-answer questions]** → Validate structurally impossible local minima, advise managers that ordinary allocation does not guarantee delivery, and expose actual evidence counts without treating missing evidence as failure.
- **[Correct answers conflict with peers]** → Use known-answer grades for designated checks and keep their peer disagreement diagnostic-only, including after key disabling.
- **[Late peer answers change earlier comparisons]** → Keep unfinished comparisons preliminary and out of scores/enforcement; evaluate only after the task reaches its target, without adding collection demand.
- **[A window expires while a worker is inactive]** → Track the next invalidation, schedule repair, and let reads detect missed refreshes without pausing access or waiting for a new submission.
- **[Source corrections race admission or recalculation]** → Mark affected calculations for refresh, prevent obsolete publication, and order completed restriction changes with issuance under database locks.
- **[Recalculation is delayed]** → Accept that an allowed worker may receive more tasks before a new restriction takes effect, or an existing restriction may last until repair/reinstatement. Keep pending updates visible and retry failed jobs; never convert that delay into a new worker pause.
- **[Scores and access reasons drift apart]** → Publish them as one derived project/worker result and retain manual recovery as an attributable input.
- **[New workers cannot earn required local history]** → Permit project-local participation with insufficient evidence; use independently earned organization/global evidence for established-history entry requirements.
- **[Scoring and enforcement become a generic rules system]** → Keep a bounded configuration and application-owned algorithm; add only lifecycle-specific resources.
- **[Global scores combine incompatible local assumptions]** → Evaluate eligible evidence under platform rules instead of averaging local scores; keep private organization evidence inaccessible.
- **[Future pay changes surprise workers]** → Keep quoted rate and bonus rules in immutable funded Finance offers; apply later changes to future work.

## Migration Plan

This request creates planning artifacts only. Runtime implementation will add resources and explicit capability grants without modifying existing global users, form/question identities, task inputs, submitted answers, review chains, or sealed export bytes.

Existing active projects retain their pre-reputation admission behavior. New draft configuration resolves on activation; adding defaults must not silently opt active projects into enforcement. Historical evidence can be assessed only under the explicitly chosen scope/window/provenance rules, never by inventing historical known-answer keys. Global eligibility and disclosure must be settled before enabling global admission.

Test migration up/down/reapply in a disposable database containing existing collection evidence. Deployment rollback must preserve newly created keys, correction histories, and reinstatement records rather than dropping authoritative evidence. Keep additive tables and disable use through a controlled deployment rollback; reconcile pending jobs before resuming enforcement. No production cleanup/destructive downgrade is authorized by this plan.

## Decisions to Finalize Before Implementation

The discussion approved the behavior and boundaries above, not a calibrated formula. The first task must record these choices and reconcile the affected scenarios before runtime work begins:

- Exact score normalization/combination for established inputs, reliability semantics and original-event timestamps, application-owned weight values and validation, minimum sample defaults, window duration/count defaults, and score-threshold inclusivity. Central weights, the three evidence states, separate pending-refresh metadata, combined-score availability, time-window boundaries, and expiration behavior are settled above.
- Supported choice cardinality/order matching, numeric tolerance boundaries and consensus concentration, and which effective peer answers qualify. Free-text/spatial semantic grading remains out of scope.
- Organization aggregation and global eligible-evidence/disclosure rules; avoid aggregating differently configured local scores. Preserve project-local participation with insufficient evidence and independent organization/global entry evidence as specified above.
- Exact authorized capability mapping, reviewer query/notification delivery, and key correction concurrency/retry inputs. Reviewer-only access exclusion and reinstatement's new-evidence cutoff semantics are settled above.
- Concrete storage for captured snapshot order and correction/settings/reinstatement guards, plus lock ordering for source changes, peer recalculation, joint publication and allocation. Preserve the approved distinction between ordinary new evidence and invalidating corrections, keep expensive preparation outside allocation locks, and prove compatibility with current Project/User/Task/Attempt and review locking.

These are visible pre-implementation decisions, not approvals implied by documenting this change. Pay-band amounts, commercial schedules, bonus settlement details, and payment-provider selection remain in the future Finance change.
