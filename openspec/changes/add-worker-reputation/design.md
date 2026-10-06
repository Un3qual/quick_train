## Context

See [proposal.md](proposal.md) for scope. This change owns the reputation decisions approved on 2026-10-05 and previously placed in `record-future-product-architecture`. It is an implementation proposal, not evidence that reputation has shipped. The approved compensation direction is retained below as a future Finance integration contract.

Core collection already supplies immutable TaskInputs, submitted QuestionResponses, attempt provenance, append-only ReviewDecisions, frozen Projects, and sealed exports. `QuickTrain.Tasks.Reviews.QuestionReview.initial_decisions!/2` automatically accepts answered submissions, so acceptance alone is not correctness evidence. `QuickTrain.Tasks.Access.WorkerEligibility` currently serves both allocation and existing-attempt authorization; putting reputation restrictions directly into that shared filter would revoke work already issued. `AttemptAllocation` also replays allocation request keys before selecting new work. These are concrete integration boundaries for this change.

The [worker-reputation delta](specs/worker-reputation/spec.md) defines the new behavior; [projects](specs/projects/spec.md) and [task-allocation](specs/task-allocation/spec.md) extend the implemented collection contract. This change does not depend on media execution or Finance.

The 2026-10-06 review fixes below settle five gaps: actual known-answer exposure, precedence over peer disagreement, prior key exposure, unfinished comparisons, and evidence expiration. A “known-answer check” means the organization's expected-answer question, not a separate kind of worker task. Its “coverage” means how many eligible known-answer questions a particular worker has actually answered; use those explicit words in API descriptions and reports.

## Goals / Non-Goals

**Goals:**

- Keep authoritative evidence in its owning domain and make assessments reproducible, scoped, and explainable.
- Implement known-answer checks and conservative peer comparison using existing immutable task identities and typed answers.
- Make project restrictions recoverable without coupling them to account bans, answer acceptance, or payment.
- Use Ash resources, actions, relationships, policies, constraints, and generators; use existing Oban infrastructure for recalculation where asynchronous work is appropriate.

**Non-Goals:**

- A second worker identity, a general rules engine, duplicated task/review event history, or a free-form score-adjustment resource.
- A canonical-answer layer or an algorithm that mistakes majority opinion for ground truth.
- Runtime Finance structures, speculative payment-provider adapters, or a generic compensation plugin interface.

## Decisions

### 1. Separate evidence dimensions and assessment scope

Add `QuickTrain.Reputation` for derived assessments and their evaluation workflows. Keep one global User. Project assessments are most specific; organization assessments summarize evidence within that organization; global assessments follow platform-owned rules for eligible evidence and calculation. Do not average differently configured local scores into a global score.

Expose known-answer correctness, substantive human review, peer agreement, reliability, and experience separately with sample counts and the evidence window, even when a configured calculation combines them. Unknown/provisional is a real state rather than a numeric zero or perfect score. Known-answer correctness has greater influence than agreement. Strong known-answer accuracy paired with disagreement remains visible as conflicting evidence for investigation.

Attempts, submitted QuestionResponses, skips, and ReviewDecisions remain authoritative. Use effective human decisions and preserve their origin; automatic acceptances are not independent positive judgments. Skips are visible but not automatically negative. Keep contribution provenance sufficient to explain and reproduce a score without copying every source record into a parallel event store.

Alternative rejected: a single opaque reputation percentage or a global average of organization scores. Either would hide uncertainty and combine incompatible judgments.

### 2. Put known answers beside exact authored task contracts

In the current product, a batch is represented by a Project and its authored Tasks. Add keys for a Task plus its published question and exact immutable input contract; there is no need for a new Batch resource. Store typed expected answers using the existing option/input identities. An expected answer on a reusable form question alone is insufficient because correctness depends on the input revisions.

Keep distribution on ordinary task allocation for this release. Check-bearing tasks share the project's submission target and can be exhausted before later workers see them. This is best-effort evidence collection, not a guarantee that each worker sees a quiz or a configured frequency of known-answer questions. Activation must reject impossible project-local minima by comparing the required count with the number of enabled scoreable task/question keys one worker could answer, and return an advisory about shared capacity for feasible configurations. Prior organization/global evidence must be assessed under its declared scope rather than assumed absent. Show actual evaluated counts and the minimum in authorized worker assessments; skips and excluded/disabled evaluations are not tests passed or failed. Too little evidence remains unknown and cannot itself create a failure-based suspension. A separate admission rule requiring established evidence can still deny admission under its explicit cold-start policy.

This deliberately avoids adding another allocator or silently increasing task demand. Guaranteed per-worker check delivery would require a separately scoped allocation design. [Qualification tests](../add-qualification-tests/proposal.md) now have an incomplete discussion skeleton and do not implicitly supply that missing guarantee.

Start with exact choice/boolean matching and configured numeric tolerance. Reuse existing answer-family validation; do not silently interpret arbitrary strings or geometry. Ranking, set/order semantics, and numeric boundary details must be listed explicitly in the supported matching contract before enabling those families. Semantic text and spatial grading remain separate future scope.

Author checks through explicit organization/project management actions. Keep key data and the check designation out of worker-facing form/task/attempt schemas and nested GraphQL traversals, including mutation results and errors. A hidden flag on a generally readable resource is not an authorization boundary. Managers/reviewers may inspect only evidence covered by their capabilities; worker explanations cannot expose answer keys or peer answers.

Retain key authorship and one first-disclosure fact per check/user, shared across that check's key revisions. Record disclosure before returning key-bearing data through any permitted API path, including nested reads and exports; fail the disclosure if the fact cannot be retained. Serialize the first-disclosure boundary with submission, then use the committed order when evaluating whether an answer was blind. A key author or a user exposed before submission cannot contribute quality evidence for that check as either assessed worker or peer. Later permission revocation or key correction does not erase exposure, and later human review cannot turn that same answer into independent quality evidence. Disclosure after a blind submission does not retroactively invalidate it. Deny key creation/correction/disabling by anyone who has submitted an answer to that exact task/question; an independent authorized actor can make a legitimate change. These narrow exposure facts support evidence eligibility, not a duplicate task-event stream or a general audit framework. Other task results and collection counts remain intact.

Retain evaluated key/matching-rule history. Correction or disabling records actor and reason, invalidates affected derived assessments, and reevaluates restrictions while preserving immutable submissions. Reuse the repository's deliberate action and retry conventions. Surface widespread check failures for key/instruction investigation; do not introduce automatic project pausing merely because a competitor does it.

Alternative rejected: overwriting a key and losing the reason for earlier scores, or using a generic form-level answer key across different tasks.

### 3. Derive agreement only from comparable distinct peers

Group by the exact task/question/pinned input contract. Exclude the assessed worker, deduplicate peers, and ignore skips and missing answers. Compare stable identities rather than randomized presentation labels. Require both enough peers and a strong enough peer consensus before a comparison contributes. Ties and split opinion are inconclusive, not errors. Numeric comparison uses a robust center such as the median with an explicit tolerance and a concentration requirement; a median alone does not prove consensus.

For a question designated as a known-answer check, use the eligible known-answer grade and exclude that question from peer-derived scoring, peer sample counts, and restrictions. This removes both contradictory penalties and double counting. Reviewers can still investigate raw key-versus-peer disagreement as a question-quality concern. Disabling a key removes its grading contribution; it does not automatically turn the same designated check into peer-scored evidence. Correcting the key repairs assessments under the same precedence rule.

Only compare completed evidence for scoring and enforcement: the task must have reached its frozen submission target, with enough distinct eligible peers and sufficient agreement. Earlier comparisons are provisional reviewer information only. A project closed before a task reaches its target does not make that partial evidence enforceable. A current calculation may have pending comparisons; that is different from a stale calculation and does not by itself force allocation retries. This keeps a changing early majority from suspending workers and preserves the existing submission-target contract.

Measure repeated disagreement over recent comparable answers with a minimum worker sample and bounded influence weaker than correctness. A project can disable agreement scoring and enforcement for subjective questions. The normal submission target remains unchanged: a project with too few responses has no usable peer signal rather than automatically collecting additional answers.

Alternative rejected: penalizing each deviation from the current plurality or increasing collection demand to manufacture consensus. Those approaches turn sparse or subjective answers into unwarranted penalties and change the collection contract.

### 4. Freeze a small typed configuration at activation

Use direct organization defaults and draft-project overrides with one application-owned calculation. Freeze the resolved project settings under the activation transaction; later default edits affect later activations. Default editing and activation must serialize or obtain a coherent snapshot so activation cannot mix two configurations.

| Setting | Responsibility |
| --- | --- |
| Enabled signals and bounded weights | Keep signal contributions explicit and agreement weaker than correctness |
| Minimum worker and peer evidence | Distinguish established assessments from provisional history |
| Agreement thresholds and numeric tolerance | Reject ambiguous comparisons and harmless numeric variation |
| Recent-history window | Allow improvement to affect assessment |
| Admission thresholds and evidence scope | Choose the qualifying assessment for new work |
| Per-signal action | Inform reviewers or suspend new project work |

Separate a signal's scoring contribution from its enforcement action. Known-answer failures can enforce automatic suspension after enough evidence. Disagreement defaults to informing reviewers, with explicit project opt-in for suspension. Reject unsupported or inconsistent combinations during authoring/activation.

There is no customer-authored formula language, generic policy/version hierarchy, duplicate reputation-event stream, or arbitrary ReputationAdjustment resource. Retained answer-key history and calculation provenance have specific evidentiary purposes; frozen project configuration does not require a generic policy framework.

Alternative rejected: fixed global rules for every organization, or unrestricted customer formulas. The former ignores project semantics; the latter adds an unnecessary execution and compatibility surface.

### 5. Add a new-work gate without changing ongoing authorization

Add reputation admission to both fetch and direct assignment after ordinary account/organization/audience checks and after resolving an existing allocation retry, but before issuing new work. Preserve `WorkerEligibility`'s role in existing-attempt reads, writes, and receipts. Do not implement reputation suspension by writing an existing `ProjectWorkerAccess` block: those blocks intentionally revoke ongoing access.

Represent effective reputation restrictions with project/user scope, evidence and reason, and an attributable recovery path. No platform-wide account ban follows automatically. Authorized reinstatement changes access rather than fabricating better source answers or adjusting a score. Corrections must reevaluate restrictions, including reasons that no longer hold. Specify how reinstatement interacts with the same old evidence before implementation so a routine rebuild does not immediately undo it or make it permanent by accident.

Preserve the issuance boundary under races. Allocation currently locks the Project, then the worker User, then task capacity. Choose a compatible ordering for restriction changes and assessment publication, with post-lock checks and stable ordering for multi-worker recalculation. Do not introduce a lock inversion through review/submission callbacks, which hold their existing outcome/task locks. Background recalculation must publish conditionally so older results cannot overwrite newer evidence.

Assessments used for enforcement need explicit freshness. Correction/submission/review transactions must identify affected assessments as needing recalculation, with retry-safe scheduling. Before new issuance, refresh a known-stale access decision or return `retry_later`; delayed scoring must not silently bypass a configured restriction. Readers distinguish pending recalculation from a current assessment. Ordinary submission and review retain their current acceptance semantics.

Time itself can make a calculation stale. For a time window of duration W at server cutoff T, include evidence whose original event time is in (T-W, T]. Answer-derived evidence uses the original submission time; later key/review correction or completion of a peer set does not reset that age. Other time-windowed evidence uses the original event time specified for its signal, not the recalculation/job time. Retain the evaluation cutoff and the next time-dependent invalidation, no later than the earliest included observation's expiry. Schedule recalculation for that boundary and also check it on assessment reads and after allocation lock waits, so correctness does not depend on job timeliness. Calculations with an older evidence revision or cutoff cannot overwrite a newer publication. A count-only window has no clock-driven expiration, but must still use a deterministic original-event order.

On expiration, recompute the score, sample minimum, and every affected automatic restriction reason. Remove a reason that no longer meets its threshold or minimum; keep other active reasons and explicit blocks. If insufficient evidence remains, the assessment becomes unknown/provisional. This is not a positive qualification: an independent admission rule requiring established evidence still applies. The same original observations cannot regain recency merely through correction or repeated recalculation. Manual reinstatement semantics remain a separate pre-implementation decision.

Use independent database connections and deliberate barriers to verify suspension versus issuance, stale versus corrected publication, key/default edits versus activation, and retry recovery. Replaying an already committed allocation after a reputation-only suspension must return its currently authorized result, not attempt new issuance or extend the lease.

Alternative rejected: cancellation of in-flight work, reusing the shared audience block, or trusting an arbitrarily stale cached score for admission. Each violates an approved boundary.

### 6. Keep compensation commitments in Finance

Optional reputation-based pay bands and quality bonuses are approved. Organizations provide defaults and projects may override them; the future Finance activation contract resolves and freezes rate rules. A project can offer a standard rate and higher rates for sufficiently established project- or organization-scoped quality. Initial upgrades use known-answer correctness and substantive human review with minimum evidence. Peer agreement remains a monitoring and eligibility signal until its suitability for compensation has been established for that project. Competitor rates and thresholds are not QuickTrain defaults.

Historical reputation selects the rate for a future offer. A quality bonus evaluates performance on the offered work using criteria disclosed with that offer. Eligibility for better-paid projects is another use of reputation and does not imply a different price for identical work. Admission, answer acceptance, and monetary settlement are separate decisions.

Finance must show and freeze the quoted rate and bonus criteria when work is offered/fetched, with enough evidence to explain the selected band. It must reserve the maximum organization charge, including any promised conditional bonus, atomically with issuance. Later score/configuration changes affect future offers and cannot alter an issued offer's quoted rate or bonus rules. Skips, rejections, and partial answers remain task facts; the pinned rate terms determine payment treatment.

Reputation supplies scoped evidence and calculation provenance. Finance owns WorkOffers, funding reservations, settlement, ledger accounting, and payouts. This change adds no paid-offer or bonus tables and does not require a Finance implementation to complete. The future Finance change must restate these terms as behavioral specs and test rate changes, conditional bonus settlement, reservation failure, and offer/reputation races against the implemented reputation API.

Alternative rejected: retroactive rate reductions or adding a payment subsystem to make reputation useful. Frozen offers keep commitments predictable and let reputation ship independently.

### 7. Use scoped Ash operations and additive storage

Generate the Reputation domain/resources and migrations with the installed Ash tooling, then tailor them to the approved scope. Keep settings, keys/history, assessments, and recoverable restrictions distinct only where their lifecycles or authorization require it; do not create a generic policy-resource family. Use Ash UUID identities, explicit organization/project references, database constraints, and native actions/domain interfaces. No direct-Ecto exception is proposed.

Reuse the organization-capability path for management and review operations with explicit grants and fail-closed scope. Preserve external worker access through existing audience/attempt authority. Expose deliberate bounded GraphQL reads and mutations; authoring authority does not imply general read access. Do not expose global raw evidence or let a local setting change platform-owned calculations. Exact capability names and global-summary disclosure must be fixed in the implementation contract.

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
- **[Faulty keys or small samples misclassify workers]** → Preserve provisional states, counts, key history, broad-failure evidence, and correction/reinstatement workflows.
- **[Workers encounter too few known-answer questions]** → Validate structurally impossible local minima, advise managers that ordinary allocation does not guarantee delivery, and expose actual evidence counts without treating missing evidence as failure.
- **[Correct answers conflict with peers]** → Use known-answer grades for designated checks and keep their peer disagreement diagnostic-only, including after key disabling.
- **[Privileged workers know a key]** → Retain authorship/first-disclosure eligibility, forbid changing a key for one's own submitted answer, and exclude affected quality evidence in every scope.
- **[Late peer answers change earlier comparisons]** → Keep unfinished comparisons provisional and out of scores/enforcement; evaluate only after the task reaches its target, without adding collection demand.
- **[A window expires while a worker is inactive]** → Track the next invalidation, schedule repair, and check server time on reads/admission even when no job or new submission arrives.
- **[Source corrections race admission or recalculation]** → Mark affected access decisions stale, prevent obsolete publication, and order restriction changes with issuance under database locks.
- **[Scoring and enforcement become a generic rules system]** → Keep a bounded configuration and application-owned algorithm; add only lifecycle-specific resources.
- **[Global scores combine incompatible local assumptions]** → Evaluate eligible evidence under platform rules instead of averaging local scores; keep private organization evidence inaccessible.
- **[Future pay changes surprise workers]** → Keep quoted rate and bonus rules in immutable funded Finance offers; apply later changes to future work.

## Migration Plan

This request creates planning artifacts only. Runtime implementation will add resources and explicit capability grants without modifying existing global users, form/question identities, task inputs, submitted answers, review chains, or sealed export bytes.

Existing active projects retain their pre-reputation admission behavior. New draft configuration resolves on activation; adding defaults must not silently opt active projects into enforcement. Historical evidence can be assessed only under the explicitly chosen scope/window/provenance rules, never by inventing historical known-answer keys. Global eligibility and disclosure must be settled before enabling global admission.

Test migration up/down/reapply in a disposable database containing existing collection evidence. Deployment rollback must preserve newly created keys, correction histories, and reinstatement records rather than dropping authoritative evidence. Keep additive tables and disable use through a controlled deployment rollback; reconcile pending jobs before resuming enforcement. No production cleanup/destructive downgrade is authorized by this plan.

## Decisions to Finalize Before Implementation

The discussion approved the behavior and boundaries above, not a calibrated formula. The first task must record these choices and reconcile the affected scenarios before runtime work begins:

- Exact score normalization/combination, reliability semantics and original-event timestamps, valid weight bounds, minimum sample defaults, window duration/count defaults, and score-threshold inclusivity. The time-window boundary and expiration behavior are settled above. Unknown signals must not silently become zero or renormalize into established excellence.
- Supported choice cardinality/order matching, numeric tolerance boundaries and consensus concentration, and which effective peer answers qualify. Free-text/spatial semantic grading remains out of scope.
- Organization aggregation and global eligible-evidence/disclosure rules; avoid aggregating differently configured local scores. Define how the chosen evidence scope applies to admission and how newcomers can acquire evidence without a circular eligibility barrier.
- Exact authorized capability mapping, reviewer query/notification delivery, key correction concurrency/retry inputs, and recovery semantics when reinstatement meets unchanged versus new negative evidence.
- Concrete source-revision/freshness storage and lock ordering for key disclosure/submission, source changes, completed-peer recalculation, restriction publication, and allocation. Implement the specified time invalidation and prove compatibility with current Project/User/Task/Attempt and review locking.

These are visible pre-implementation decisions, not approvals implied by documenting this change. Pay-band amounts, commercial schedules, bonus settlement details, and payment-provider selection remain in the future Finance change.
