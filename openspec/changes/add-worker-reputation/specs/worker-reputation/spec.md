## Purpose

Give organizations explainable worker-quality evidence and recoverable control over future project work while preserving submitted answers, existing attempts, and organization privacy.

## ADDED Requirements

### Requirement: Scoped assessments preserve evidence and uncertainty
Reputation SHALL assess the existing global User at project, organization, and platform-controlled global scope. Assessments SHALL distinguish known-answer correctness, substantive human review, peer agreement, reliability, and experience, and expose contributing counts, the evidence window, and calculation provenance to authorized readers. Evidence state SHALL be exactly one of not applicable, insufficient evidence, or established. Disabled/unselected contributors SHALL be not applicable; enabled contributors below their minimum SHALL have insufficient evidence, including at zero observations; contributors meeting the minimum SHALL be established. Counts SHALL distinguish zero observations from a small sample without another evidence state. As-of cutoff and pending refresh SHALL be separate metadata; a pending update SHALL NOT by itself change the evidence state or deny access. Admission SHALL evaluate the latest completed inputs from each required scope on each new work request. Global calculations SHALL use platform-defined eligible evidence and SHALL NOT average scores calculated under different local settings. One organization's settings SHALL NOT change another organization's assessment or the global calculation.

#### Scenario: A new worker has insufficient history
- **WHEN** the worker has fewer observations than the configured minimum for an enabled signal
- **THEN** that signal has insufficient evidence and reports its actual count, without a fabricated success or failure score

#### Scenario: Organizations use different settings
- **WHEN** two organizations give the same worker different local assessments
- **THEN** each assessment retains its scope and provenance, and neither local score overwrites the other or becomes an unqualified global average

#### Scenario: Zero observations and a small sample use one state
- **WHEN** one enabled signal has no observations and another enabled signal has some observations below its configured minimum
- **THEN** both have insufficient evidence with their actual counts rather than separate states

#### Scenario: An established assessment awaits an update
- **WHEN** an established published assessment needs recalculation
- **THEN** its evidence state remains established as of its recorded cutoff, with pending refresh reported separately and that completed assessment still usable by a fresh admission evaluation

### Requirement: Application-owned weights are explicit calculation inputs
Score weights SHALL be defined centrally in application code and supplied explicitly to the shared reputation calculation. Organization/project management SHALL NOT accept customer-provided weight overrides in this release. Project activation SHALL retain the effective application weight values with the frozen configuration; subsequent default-weight changes SHALL NOT silently reweight active projects. Organization/global assessments SHALL retain their effective platform-owned weight values and calculation provenance. A platform weight change for those scopes SHALL invalidate affected assessments and use the normal recalculation/publication path. Equivalent evidence, effective settings, and weight inputs SHALL produce the same result across reads, jobs, reports, and admission. Global reputation SHALL remain independent of organization/project configuration. Adjustable customer weights are deferred; numerical defaults and normalization for established inputs remain pre-implementation decisions.

#### Scenario: Application weights change after project activation
- **WHEN** developers change the central weight definition
- **THEN** new project activations use the new weights while already-active projects retain their frozen values, and rebuilt results remain attributable to the effective inputs used

#### Scenario: An organization attempts to override weights
- **WHEN** an authorized manager supplies score weights through organization or project configuration
- **THEN** the unsupported override is rejected rather than changing the calculation or global reputation

### Requirement: Disabled and insufficient signals have distinct scoring outcomes
A scoring signal disabled by the effective configuration SHALL be not applicable and contribute neither a value nor weight to the combined calculation. Each combined result SHALL identify its contributing signal set; an admission result SHALL exclude reviewer-only signals and their minimum-evidence requirements. An enabled contributing signal with insufficient evidence SHALL remain in the insufficient-evidence state; it SHALL NOT receive a zero/success value or have its weight silently redistributed among established signals. A combined score SHALL be established only when every contributing enabled signal meets its minimum. Otherwise the combined numeric score SHALL be unavailable while individual established metrics and all applicable counts remain inspectable. A configuration with no contributing signals SHALL yield a not-applicable combined result. Established individual signals SHALL remain eligible for their own configured actions without waiting for unrelated signals. Insufficient combined admission evidence SHALL follow the existing project-local insufficient-evidence and established organization/global entry rules.

#### Scenario: Human-review scoring is disabled
- **WHEN** the effective configuration disables human-review scoring and all other contributing signals have sufficient evidence
- **THEN** the combined score is calculated from the selected signals without including human review as a zero or missing requirement

#### Scenario: Human-review scoring is enabled but has too little evidence
- **WHEN** known-answer accuracy is established but an enabled contributing human-review signal has not met its minimum
- **THEN** known-answer accuracy remains inspectable and eligible for its configured action, while the combined score has insufficient evidence with no usable numeric value

#### Scenario: No scoring signals are selected
- **WHEN** the effective configuration contains no contributing scoring signals
- **THEN** the combined result is not applicable rather than zero or perfect reputation

### Requirement: Review and task facts retain their meaning
Assessments SHALL derive from authoritative submitted answers, attempts, known-answer keys, and review evidence. Automatic acceptance of submitted answers SHALL NOT count as independent evidence of correctness. Human-review evidence SHALL retain its effective verdict and provenance; a rejection SHALL NOT be treated as an answer key. Skips SHALL remain distinguishable and SHALL NOT automatically reduce quality. Reputation SHALL NOT rewrite worker answers, issue review verdicts, select canonical answers, change submission targets, create replacement demand, or reopen satisfied tasks.

History windows SHALL select inputs for a calculation, not define source-data retention. Excluding evidence from a window SHALL NOT delete submitted answers, review history, or retained key history.

#### Scenario: Automatic review accepts every answer
- **WHEN** an automatically reviewed project accepts a worker's submissions
- **THEN** those acceptances do not increase substantive human-review quality or substitute for known-answer grading

#### Scenario: A quality concern follows task completion
- **WHEN** reputation detects repeated disagreement after a task reaches its submission target
- **THEN** the task stays satisfied and its responses, review verdicts, and sealed exports remain unchanged

#### Scenario: A calculation uses only part of the stored history
- **WHEN** a history window selects twenty observations from a larger stored history
- **THEN** only the selected observations enter that calculation while the unselected source evidence remains stored and unchanged

### Requirement: Known-answer checks bind to exact task evidence
Authorized organization managers SHALL be able to include known-answer checks among ordinary project work. Each key SHALL identify the exact published question, task, immutable revision inputs, and relevant option or input identities. A key SHALL NOT apply to every instance of a reusable form question merely because its question identity matches. Initial supported checks SHALL use exact choice/boolean matching and configured numeric tolerance. Unsupported grading families SHALL be rejected explicitly rather than silently scored; semantic free-text and spatial grading SHALL remain unsupported until separately specified.

#### Scenario: A question is reused for different inputs
- **WHEN** two tasks use the same published question with different immutable inputs
- **THEN** a key for one task does not grade the other task

#### Scenario: Presentation order is randomized
- **WHEN** the worker selects an input displayed in a different position from the author's presentation
- **THEN** grading compares the stable option/input identity rather than an A/B label or position

#### Scenario: A numeric answer is within tolerance
- **WHEN** a numeric answer is within the key's configured tolerance
- **THEN** it passes that check and the evaluated tolerance is retained with the grading provenance

#### Scenario: An unsupported key is supplied
- **WHEN** an author requests semantic free-text or spatial grading without an implemented grading contract
- **THEN** key authoring fails with a scoped validation error and creates no scoreable check

### Requirement: Known-answer evidence reflects actual evaluated answers
A known-answer check SHALL mean a question with an organization-supplied expected answer for its exact task inputs. Such questions SHALL follow ordinary task allocation and submission capacity; this release SHALL NOT guarantee a check frequency or minimum number of checks for each worker. Authorized assessment reads SHALL report each worker's actual evaluated known-answer count, its configured minimum, and whether that minimum is met. Skipped and disabled checks SHALL NOT count as evaluated successes or failures. When known-answer scoring is enabled, exhaustion of authored checks or insufficient observations SHALL leave the signal in the insufficient-evidence state and SHALL NOT itself trigger a poor-quality suspension. Insufficient project-local history SHALL permit participation, without bypassing a separately configured requirement for established organization/global evidence or any other valid access restriction. Reports SHALL NOT imply that every worker was tested merely because the project contains known-answer questions.

#### Scenario: Earlier workers consume the available known-answer tasks
- **WHEN** known-answer scoring is enabled and ordinary allocation satisfies those tasks before another worker encounters them
- **THEN** the later worker's known-answer count remains zero and the signal has insufficient evidence, without a fabricated score or a failure-based suspension

#### Scenario: A worker sees questions but does not produce evaluable answers
- **WHEN** a worker skips known-answer questions or their evaluations are excluded
- **THEN** those observations do not satisfy the evaluated-answer minimum and the assessment reports the actual eligible count

### Requirement: Organizations can inspect known-answer evidence and question quality
Authorized organization reviewers SHALL have scoped worker reports showing evaluated known-answer count, correct and incorrect counts, accuracy when the evaluated count is nonzero, configured minimum, and whether that minimum is met. Worker reports SHALL use the worker assessment's configured history window and identify its configuration, key provenance, evaluation cutoff, and freshness. Reports SHALL reuse the assessment's evidence state: disabled/unselected scoring SHALL be not applicable, while enabled scoring below its minimum SHALL have insufficient evidence. A zero count alone SHALL NOT determine that state or make a disabled signal appear to have an unmet minimum.

Question-quality reports SHALL instead summarize all evaluable submitted answers to one exact task/question/input contract through the report cutoff, independently of workers' reputation windows and reinstatement cutoffs. They SHALL report evaluated, correct, and incorrect counts and match rate when evaluable answers exist. They SHALL identify the evaluated key revision, all-history sample, cutoff, and freshness; a report SHALL NOT mix evaluations from different key revisions. Corrections and enabled-state changes SHALL refresh these reports through the existing recalculation path. A completed report awaiting refresh SHALL identify its pending update and evaluated key rather than present obsolete grading as current. No additional configurable report window SHALL be introduced. Work on other questions or the passage of a worker's history-window boundary SHALL NOT remove answers from this question's sample.

Skipped and disabled evaluations SHALL NOT enter current accuracy denominators. A zero denominator SHALL yield unavailable accuracy rather than a success or failure rate, and enabled scoring with insufficient worker history SHALL retain its insufficient-evidence status. Question outcome summaries SHALL be diagnostic: widespread failure alone SHALL NOT declare a key invalid, disable it, pause a project, or add an automatic worker restriction. Reviewers SHALL use the authorized key correction/disabling/re-enabling and recalculation actions when investigation warrants a change. These reports SHALL NOT require extra worker interactions, change reputation windows or source retention, or disclose protected evidence to workers.

#### Scenario: Perfect accuracy has little supporting evidence
- **WHEN** one worker answers eighteen of twenty known-answer questions correctly and another answers two of two correctly within their assessment windows
- **THEN** reviewers see both counts and the corresponding 90% and 100% accuracy, together with each worker's minimum-evidence status

#### Scenario: Enabled known-answer scoring has no evaluated responses
- **WHEN** known-answer scoring is enabled and the organization reads a worker's report with no evaluated known-answer responses
- **THEN** it shows zero evaluated answers, unavailable accuracy, and insufficient-evidence history rather than implying that the worker passed or failed

#### Scenario: Known-answer scoring is disabled
- **WHEN** the organization reads a worker's report under a configuration that disables known-answer scoring
- **THEN** the report reuses the assessment's not-applicable state without presenting an unmet minimum, including when the evaluated count is zero

#### Scenario: Most workers disagree with a supplied key
- **WHEN** only ten of one hundred eligible evaluated responses match a question's key
- **THEN** authorized reviewers can inspect the counts and 10% match rate to investigate the key or instructions, without the report automatically changing the key, project state, or worker restrictions

#### Scenario: Workers move on to later questions
- **WHEN** two of ten answers match a question's key and those workers later answer enough other questions to move the original answers outside their reputation windows
- **THEN** the question report still shows two of ten matching that key, while worker reports follow their own windows and all source answers remain stored

#### Scenario: A key correction changes the question report
- **WHEN** a corrected key changes which stored answers match
- **THEN** the refreshed question report evaluates the same all-history sample under the corrected key, identifies its revision, and does not mix old and new grades or restore expired answers to worker reputation windows

### Requirement: Keys and check designations remain private
Worker presentation SHALL use the ordinary question/input contract without disclosing the answer key or the designation of a question as a quality check. Worker-facing APIs, nested GraphQL traversal, errors, and work-access outcomes SHALL NOT reveal hidden keys, other workers' answers, or another organization's private evidence. A worker account SHALL NOT gain manager access by holding an attempt. Authorized organization reviewers SHALL be able to inspect only the supporting evidence permitted by their scoped authority. Detailed worker-facing reputation explanations and dispute workflows are deferred; organization reviewer evidence and recovery actions remain in scope.

Authorized key authors/readers who also perform work SHALL follow the ordinary reputation evidence rules. Prior key knowledge alone SHALL NOT exclude their answers or prohibit an otherwise authorized key edit. No key-disclosure tracking or special reveal workflow is required. Existing organization authorization, key-change attribution, and human-review rules remain effective.

#### Scenario: An external worker inspects a work bundle
- **WHEN** an eligible external worker reads a task containing a known-answer check
- **THEN** ordinary task content is available without organization membership, while check designation, key, and manager-only relationships remain inaccessible

#### Scenario: A worker follows nested relationships
- **WHEN** a worker requests key data or other workers' answers through an attempt, task, question, or assessment relationship
- **THEN** the request grants no access to that protected evidence

#### Scenario: A key author also performs work
- **WHEN** an otherwise eligible user who authored a key submits an evaluable answer to that question
- **THEN** the answer follows ordinary grading and reputation rules without an exclusion based on authorship

### Requirement: Key corrections preserve history and repair assessments
Authorized corrections, disabling, or explicit re-enabling of an existing key SHALL retain the prior key, matching rule, enabled/disabled state, actor, reason, and evaluation provenance. An ordinary correction SHALL preserve the key's enabled/disabled state; correcting a disabled key SHALL NOT silently resume grading. An authorized manager SHALL be able to explicitly re-enable an existing corrected key. Corrections and enabled-state changes SHALL use the same retained history and recalculation workflow without mutating submitted answers. Re-enabling SHALL restore eligible grading under the current key and existing scope/window rules, preserving each answer's original observation identity and submission time. Repeated action requests SHALL NOT duplicate transitions or contributions. Each correction or enabled-state change SHALL cause affected assessments and reputation restrictions to be reevaluated; obsolete evaluations SHALL NOT remain effective after recalculation or overwrite a newer result. Review corrections SHALL likewise feed recalculation. Reviewers SHALL have evidence to identify widespread key failures and investigate potentially incorrect keys or instructions.

#### Scenario: A wrong expected answer penalizes workers
- **WHEN** an authorized manager corrects or disables that key
- **THEN** its old evaluation remains explainable, affected assessments are recalculated, and restrictions based on the faulty evidence are reevaluated without editing submissions

#### Scenario: A stale recalculation finishes later
- **WHEN** a calculation using an older key or review finishes after a calculation using its correction
- **THEN** it cannot restore the obsolete assessment or restriction

#### Scenario: A disabled key is corrected
- **WHEN** an authorized manager corrects a disabled key's expected answer or matching rule
- **THEN** the correction is retained while the key remains disabled and contributes no current known-answer grading

#### Scenario: A corrected key is explicitly re-enabled
- **WHEN** an authorized manager re-enables an existing corrected key
- **THEN** the attributed state change triggers normal recalculation using the current key and eligible stored answers, preserving original observation identities and submission times rather than duplicating contributions or making old answers recent

### Requirement: Peer comparison requires sufficient comparable evidence
Peer agreement SHALL compare submitted answers from distinct workers to the same question and exact task inputs under the same pinned contract. It SHALL exclude the assessed worker's answer, duplicate votes from one peer, skips, and absent answers. A comparison SHALL contribute only when the configured minimum number of peers and agreement threshold are met. Ties, sparse evidence, and split opinion SHALL provide no negative disagreement signal. Identity comparisons SHALL use canonical option/input identities; supported numeric comparisons SHALL use a robust center and configured tolerance.

#### Scenario: The worker would create their own majority
- **WHEN** the assessed worker's answer would cause a label to pass the agreement threshold
- **THEN** that answer is excluded before deciding whether the peers establish a usable comparison

#### Scenario: Peer opinion is split
- **WHEN** other workers tie or do not reach the configured agreement threshold
- **THEN** the comparison supplies no negative signal for any worker

#### Scenario: Retry evidence is encountered during a rebuild
- **WHEN** the same peer's submission is encountered more than once
- **THEN** that peer contributes at most one vote to the comparison

### Requirement: Repeated disagreement is weaker than correctness
Disagreement assessments SHALL require a minimum worker sample and repeated comparable observations within the configured recent-history window. One unusual answer SHALL NOT establish consistently poor reputation. Agreement's scoring contribution SHALL be bounded and weaker than known-answer correctness. Projects SHALL be able to disable agreement scoring and enforcement when consensus does not represent quality. Conflicting strong correctness and unusual disagreement SHALL remain distinguishable to reviewers.

#### Scenario: A subjective preference project disables agreement
- **WHEN** its workers give differing opinions
- **THEN** those differences do not reduce reputation or trigger disagreement-based restrictions

#### Scenario: A correct worker disagrees with peers
- **WHEN** a worker has strong known-answer accuracy and repeated peer disagreement
- **THEN** reviewers can see both signals and their sample counts instead of receiving an unexplained poor-quality label

### Requirement: Known-answer grading takes precedence over peer disagreement
A question designated as a known-answer check SHALL use its eligible known-answer evaluation rather than peer agreement as quality evidence for that answer. Peer disagreement on that question SHALL NOT contribute to a worker's score, peer sample minimum, or automatic restriction, even when disagreement enforcement is independently enabled. Authorized reviewers SHALL be able to inspect key-versus-peer conflicts as possible key, instruction, or peer-quality problems. Disabling a key SHALL remove its grading contribution without automatically converting the designated check into peer-scored evidence. Correcting a key SHALL recalculate its contribution and dependent restrictions under the same precedence rule.

#### Scenario: The majority gives the wrong answer to a known-answer question
- **WHEN** a worker matches the active key but other workers agree on a different answer
- **THEN** the worker receives the eligible known-answer outcome and no contradictory disagreement penalty or suspension from that question

#### Scenario: A questionable key is disabled
- **WHEN** an authorized actor disables a key after conflicting responses are found
- **THEN** its grading stops contributing and the same question does not become a new source of peer-based penalties

### Requirement: Unfinished peer comparisons cannot restrict work
Peer comparisons SHALL become eligible for reputation scoring and enforcement only when the task reaches its frozen submission target and the final distinct-peer sample satisfies the configured minimum and consensus threshold. Earlier comparisons SHALL be labeled preliminary and available only as authorized reviewer information; they SHALL NOT contribute to scores or admission/restriction decisions. Completing a project before a task meets its target SHALL NOT convert that partial comparison into enforceable evidence. A current assessment containing pending comparisons SHALL remain distinguishable from a stale calculation; unfinished evidence alone SHALL NOT cause indefinite allocation retries. Insufficient local history SHALL permit participation; separately configured established organization/global entry requirements SHALL still apply.

#### Scenario: An early majority reverses
- **WHEN** early submitted answers favor one option but the final submitted set favors another
- **THEN** the early comparison causes no score change or suspension, and only the completed eligible comparison contributes

#### Scenario: A project closes with a partially answered task
- **WHEN** completion cancels remaining capacity before the task's submission target is met
- **THEN** its peer comparison remains non-enforcing and collection is not reopened to obtain more answers

### Requirement: Signal actions support review and recoverable project suspension
Each enabled signal SHALL support a configured action to inform reviewers or suspend new project work after its minimum evidence and threshold conditions are met. Reviewer-only signals MAY contribute to authorized reviewer summaries, but SHALL NOT restrict work directly or indirectly through combined admission scores, minimum-evidence requirements, or pending recalculation. Every automatic access calculation SHALL use only the contributing signals enabled for that purpose in the frozen project configuration. Organization/global entry rules SHALL use the eligible per-signal inputs rather than an aggregate containing excluded signals; this SHALL NOT alter the independent organization/global assessment. Known-answer failures SHALL support automatic suspension. Disagreement SHALL default to informing reviewers and SHALL require explicit project opt-in for any automatic access effect. Automatic restrictions SHALL be project-scoped and SHALL NOT impose platform-wide account bans. Authorized reviewers SHALL receive the reason and supporting evidence; authorized managers SHALL be able to reinstate selected project-local automatic rules without changing the underlying answers or fabricating a score adjustment. Reinstatement and recalculation SHALL have attributable, repeatable outcomes.

#### Scenario: Known-answer failures cross an enforced threshold
- **WHEN** enough evaluated checks establish failure under a project's configured automatic action
- **THEN** the worker is suspended from new work in that project with a reason inspectable by authorized organization reviewers

#### Scenario: Repeated disagreement uses the default action
- **WHEN** disagreement exceeds its threshold without explicit automatic-suspension opt-in
- **THEN** authorized reviewers receive the concern, but disagreement does not affect automatic admission or suspension, including through a combined score

#### Scenario: A broader score includes reviewer-only disagreement
- **WHEN** a project's entry rule uses global evidence but treats disagreement as reviewer-only
- **THEN** it uses only the eligible global signal inputs for admission rather than the aggregate containing disagreement, without changing the global assessment

#### Scenario: Only reviewer-only evidence is missing or pending
- **WHEN** the worker satisfies the project's automatic rules using current access-relevant evidence but a reviewer-only signal lacks enough evidence or awaits recalculation
- **THEN** that signal remains labeled appropriately for reviewers without making eligible admission evidence insufficient, denying access, or causing a retry

#### Scenario: A reviewer reinstates a worker
- **WHEN** an actor with reinstatement authority acts on a project restriction
- **THEN** the action records its reason and effect without granting access in another project or changing historical task evidence

### Requirement: Reinstatement evaluates selected rules using subsequent evidence
An authorized reinstatement SHALL identify the project, worker, selected project-local automatic rule(s), actor, explanation, related prior decision, and effective cutoff. Each selected rule SHALL evaluate only eligible evidence with an original source-event time after its latest reinstatement cutoff, within its existing history window and using its existing minimum samples and threshold. Answer-derived evidence SHALL use the original answer submission time; later review, peer completion, key correction, or rebuilding SHALL NOT renew that time. Insufficient post-reinstatement evidence SHALL permit participation under that rule; sufficient new evidence SHALL be eligible to trigger it again. A selected combined rule SHALL require its eligible contributors' existing minima from that subsequent evidence. Historical reputation and reviewer metrics SHALL remain unchanged by reinstatement, and unselected automatic rules, explicit blocks, and independent organization/global entry requirements SHALL remain effective. Replaying the same reinstatement request SHALL retain the original cutoff. Recalculation and expiration SHALL preserve the cutoff; a deliberate later reinstatement MAY establish a new one. No separate recovery thresholds, recovery score, or blanket exemption duration SHALL be introduced.

#### Scenario: Rebuilding old failures after reinstatement
- **WHEN** a worker has been reinstated for a known-answer failure rule and its old answers are regraded or rebuilt
- **THEN** historical reputation reflects those answers but they cannot satisfy the selected rule's post-reinstatement minimum or restore its old suspension

#### Scenario: New evidence reaches the existing failure threshold
- **WHEN** enough eligible post-reinstatement answers meet the selected rule's existing minimum and fail its configured threshold
- **THEN** the rule can suspend new work again with attributable evidence, without a new recovery policy

#### Scenario: Another rule still denies entry
- **WHEN** reinstatement clears one rule but another automatic rule, explicit block, or independent organization/global entry requirement still denies access
- **THEN** the remaining rule continues to deny entry and the reinstatement does not grant a general access override

#### Scenario: A reinstatement request is retried
- **WHEN** the same successful reinstatement request is replayed after additional answers arrive
- **THEN** it retains its original cutoff and effect rather than restarting the evidence period

### Requirement: Assessments publish coherent completed results
Each scoped assessment SHALL publish its scores, contributing counts, evidence provenance, and freshness together from one coherent fixed snapshot of source evidence, evaluation cutoff, effective settings, and applicable reinstatement inputs. Project assessments SHALL retain any rule-specific post-reinstatement inputs with that same publication. Project assessments SHALL NOT cache organization/global admission outcomes that must be refreshed before those newer scoped assessments can be used. Automatic access reasons SHALL be derived from completed assessment inputs during admission, not maintained as separate suspension state.

Publication SHALL advance the completed snapshot by captured input order rather than job completion time, without regressing the published source frontier or evaluation cutoff. Ordinary new answers or a time-window refresh boundary reached after capture SHALL NOT invalidate an otherwise valid result; they SHALL request a follow-up calculation and retain pending-refresh metadata. Key/review corrections, key disabling or re-enabling, changes to effective settings, or reinstatement SHALL invalidate affected prepared results. A result using superseded protection inputs or an older snapshot SHALL NOT replace the effective publication. Reinstatement SHALL remain separately attributable and serialized with publication/admission without rewriting evidence or historical scores.

#### Scenario: New answers arrive during calculation
- **WHEN** a calculation has captured its inputs and more ordinary answers arrive before it finishes
- **THEN** its valid result can publish if it advances the completed snapshot, retaining its original cutoff and pending refresh for the additional answers instead of repeatedly restarting

#### Scenario: A correction invalidates a prepared calculation
- **WHEN** a key/review correction, key disabling or re-enabling, effective-setting change, or reinstatement supersedes inputs used by a prepared result
- **THEN** that result is discarded and preparation repeats under the new inputs without overwriting a newer publication or pausing admission using completed assessments

#### Scenario: A faulty key is repaired
- **WHEN** a completed recalculation removes the evidence supporting an automatic suspension
- **THEN** the next admission evaluation uses the repaired assessment and no longer derives that failure reason, while unrelated valid reasons and explicit blocks remain effective

#### Scenario: Publication fails partway through
- **WHEN** publishing a new assessment fails before commit
- **THEN** none of its updated metrics become effective; admission continues to evaluate the previous completed inputs, and readers can see that the assessment needs updating

### Requirement: New work evaluates the latest completed assessments
Each request for new project work SHALL evaluate the frozen project's automatic rules using the latest completed assessment inputs in each required project, organization, or global scope, together with applicable reinstatement and current ordinary authorization. It SHALL select only access-relevant signals and apply their existing minima, weights, and thresholds. A prior denial SHALL NOT be a lasting restriction independent of those inputs. Once a required organization/global assessment improves enough, a new request SHALL be able to qualify without a separate project refresh job or manual clearing of that earlier denial. Newly completed evidence establishing failure SHALL likewise affect subsequent issuance without waiting for a project-specific copy of the broader result.

Access evaluations SHALL retain their outcome, reasons, time, effective settings, assessment references/as-of cutoffs, and reinstatement provenance as scoped decision history. Retaining an earlier outcome SHALL NOT make it authoritative for a later new-work request. Replaying an already committed allocation SHALL retain the existing allocation retry contract instead of rechecking reputation for new issuance.

#### Scenario: A denied worker earns enough broader reputation
- **WHEN** Project B previously denied a worker for insufficient broader reputation, a new organization/global assessment now satisfies that requirement, and the worker requests new work in B
- **THEN** admission uses the improved completed assessment without a B-specific refresh or manual reinstatement, permits work if all other requirements are met, and retains the previous denial as history

#### Scenario: Broader reputation now fails an entry rule
- **WHEN** a previously qualifying worker's latest completed organization/global assessment fails the project's configured entry rule
- **THEN** a new work request is denied using that result even if the project's local assessment has not changed, without revoking issued work

### Requirement: Pending recalculation keeps completed assessment inputs usable
Pending recalculation, source corrections, and time-window expiry SHALL mark affected assessments as needing refresh without withdrawing their completed inputs from admission. Authorized reads and decision history SHALL expose each input's as-of cutoff and pending update rather than present an old calculation as fresh. Fetch and direct assignment SHALL evaluate the latest completed inputs from each required scope even if another required scope awaits refresh. A pending scope SHALL NOT prevent use of a newer completed assessment in another scope.

A previously allowed worker SHALL NOT receive a new restriction, a reputation-updating retry response, or a grace-period timeout solely because recalculation is incomplete. With unchanged completed inputs, effective rules, and reinstatement, the reputation outcome SHALL remain unchanged. A prior denial SHALL continue only while the rules evaluated against those inputs still deny access. Ordinary account, organization, audience, explicit-block, lease, and capacity rules SHALL remain effective. Changed outcomes from newly completed assessments SHALL affect only subsequent issuance and SHALL NOT invalidate already-issued work.

#### Scenario: A global assessment is awaiting repair
- **WHEN** a key correction marks a contributing global assessment stale but recalculation is delayed
- **THEN** reports show the pending update and admission uses its last completed inputs alongside the latest completed inputs in other required scopes, without a scoring pause

#### Scenario: Supporting evidence expires before local evidence
- **WHEN** a required organization/global assessment reaches its expiration boundary while local evidence remains current
- **THEN** refresh is requested and admission continues to use completed inputs without a temporary pause

#### Scenario: An existing suspension awaits recalculation
- **WHEN** the assessments behind a denial await recalculation and their completed inputs, applicable reinstatement, and effective rules remain unchanged
- **THEN** another request produces the same reputation outcome; the pending job alone neither lifts nor adds a restriction

#### Scenario: Global reputation improves while local refresh remains pending
- **WHEN** a previously denied worker's global assessment now satisfies the entry rule and the completed local inputs already permit participation but await refresh
- **THEN** a new request can qualify using those completed inputs without waiting for the local refresh

### Requirement: First access does not depend on a queued initial calculation
If any required initial assessment is missing, the ordinary admission request SHALL authorize preparation, detect committed allocation retries, and calculate the missing assessment from eligible evidence before entering the allocation transaction or taking its Project/User/task locks. Unprocessed history SHALL NOT be classified as absent or require a queued-job wait. Completed inputs awaiting refresh SHALL remain usable with their pending/as-of metadata.

Under allocation locks, the request SHALL recheck current authorization, project state/configuration, the request key, the latest completed assessments in all required scopes, and reinstatement. It SHALL use concurrently completed assessments when available; otherwise it SHALL validate and publish the needed prepared candidates under the fixed-snapshot guards before evaluating admission. If a guard changed and a required completed assessment is still missing, it SHALL release allocation locks before preparing again in the request. Evidence scans, peer comparisons, and full history calculations SHALL NOT run while allocation locks are held; bounded rule evaluation over completed assessment metrics SHALL be permitted. Insufficient local evidence SHALL permit participation while configured organization/global entry requirements remain effective. No queued warm-up lifecycle, qualification attempt, or reputation-updating retry outcome SHALL be introduced.

#### Scenario: Eligible prior history has not been assessed yet
- **WHEN** a worker requests their first task in a project and required eligible organization/global evidence exists but its initial assessment job has not run
- **THEN** admission prepares the missing assessments outside allocation locks, then revalidates and publishes or uses concurrent completed assessments before evaluating issuance without waiting for the queued job

### Requirement: Reputation operations fail closed within organization scope
Organization settings, keys, assessments, access-decision history, reviewer information, and restriction management SHALL require explicit organization scope and operation-appropriate management or review authority. Organization management SHALL require an active authenticated account, active organization, active membership, and explicit capability grants. Foreign and nonexistent targets SHALL fail without distinguishable disclosure. Worker sessions SHALL require an account while retaining existing optional-membership audience routes. Platform-controlled global summaries SHALL NOT disclose other organizations' raw evidence or grant management access.

#### Scenario: A reviewer supplies another organization's assessment
- **WHEN** an otherwise authorized reviewer substitutes a foreign organization, project, worker assessment, or key reference
- **THEN** the operation discloses and changes no unauthorized record

#### Scenario: Management authority is revoked
- **WHEN** a manager loses the required capability or active membership before a mutation commits
- **THEN** the mutation fails closed without partial changes

### Requirement: Recalculation is reproducible and safe to repeat
Assessments SHALL be rebuildable from retained authoritative evidence and the applicable scoped configuration. Equivalent evidence and calculation inputs SHALL yield equivalent assessments. Repeated calculation, submission retries, key corrections, and review retries SHALL NOT double-count evidence or duplicate restriction effects. Readers SHALL be able to distinguish a pending recalculation from an up-to-date calculation and identify the completed inputs used for each access evaluation. Repeated jobs SHALL preserve completed inputs until a replacement publishes; pending work SHALL NOT itself create or clear a restriction, and historical denials SHALL NOT override a fresh admission evaluation.

#### Scenario: A rebuild runs twice
- **WHEN** the same evidence and configuration are evaluated again
- **THEN** scores, counts, and effective restriction outcomes converge without duplicate penalties

#### Scenario: Admission needs an assessment under repair
- **WHEN** corrected evidence makes a required assessment stale before a worker fetches new work
- **THEN** allocation evaluates the latest completed assessment inputs with applicable reinstatement and ordinary authorization while the repaired result is calculated

### Requirement: Count windows select recent eligible observations per signal
For a count-only window with positive integer limit N, each signal SHALL independently select at most N eligible observations from the captured evidence snapshot. Selection SHALL first apply the declared scope, signal eligibility, source deduplication, evaluation cutoff, and any applicable reinstatement cutoff, then take the most recent observations by original source-event time. Equal event times SHALL use a stable source-observation identity as a deterministic tie-breaker, consistently across calculations and rebuilds. Correct and incorrect eligible known-answer evaluations SHALL both count; ineligible evidence and evidence for other signals SHALL NOT consume that signal's slots. If fewer than N observations qualify, the calculation SHALL use the actual available count and retain the existing minimum-evidence rules.

Answer-derived observations SHALL use original answer submission time; other signals SHALL use their defined original event time. Corrections SHALL update the same logical observation without adding a duplicate, changing its original event time, or changing its source-identity tie-breaker. An eligibility change SHALL rerun selection, allowing the next most recent eligible observation to fill an available slot. Count-only windows SHALL have no clock-driven expiration. Window selection SHALL preserve source history and SHALL NOT alter submission targets.

#### Scenario: Ordinary answers do not crowd out known-answer evidence
- **WHEN** a worker has more than twenty eligible graded known-answer responses interspersed with ordinary answers, skips, and disabled-key evaluations, with a count limit of twenty
- **THEN** the known-answer signal uses its twenty most recent eligible graded responses, including correct and incorrect answers, while other signals select their own evidence independently

#### Scenario: Reinstatement leaves fewer eligible observations than the window limit
- **WHEN** a selected local rule has five eligible observations after its reinstatement cutoff and a count limit of twenty
- **THEN** it uses those five without filling the remaining slots from pre-reinstatement evidence, applies its existing minimum, and leaves historical reputation unchanged

#### Scenario: Observations share a timestamp at the selection boundary
- **WHEN** more eligible observations share the boundary timestamp than fit in the remaining slots
- **THEN** the stable source-identity tie-breaker selects the same observations on equivalent rebuilds regardless of query or job completion order

#### Scenario: A correction changes an eligible answer's grade
- **WHEN** an answer is regraded and remains eligible
- **THEN** its corrected grade occupies the same original observation and ordering position rather than becoming a new recent observation or a second contribution

#### Scenario: A key is disabled for a selected observation
- **WHEN** disabling a key makes a selected known-answer observation ineligible
- **THEN** selection excludes it before applying the count limit and uses the next most recent eligible observation if available, without deleting the excluded source evidence

### Requirement: Time windows expire evidence without requiring a new submission
Each time-windowed assessment SHALL record its evaluation cutoff and next time-dependent invalidation, if any. Answer-derived observations SHALL be dated by the original answer's submission time; other time-windowed evidence SHALL use its signal's original event timestamp rather than job time. Key correction, delayed peer completion, and review correction SHALL NOT restart an observation's age. For duration W at cutoff T, eligible observations SHALL have original event times greater than T minus W and no later than T. The next invalidation SHALL be no later than the earliest included observation's original event time plus W. At or after that boundary, reads SHALL identify the calculation as needing refresh; scheduled recalculation and detection of a missed boundary SHALL request repair without requiring a new submission. Pending repair SHALL NOT pause allocation or make completed inputs unusable. Recalculation SHALL publish updated metrics with retained reinstatement cutoffs. Admission SHALL use those completed metrics to remove failure-based reasons whose threshold or minimum is no longer met, preserving other valid reasons, explicit blocks, and separate established organization/global entry requirements. If remaining local history falls below the minimum, the replacement SHALL report insufficient evidence and admission SHALL permit participation under that local rule, without fabricating a success score.

#### Scenario: A suspended worker produces no new answers
- **WHEN** the evidence supporting an automatic suspension expires out of the window
- **THEN** time-driven recalculation reevaluates it without requiring a new submission, and a fresh admission evaluation uses the completed result to remove the unsupported reason while retaining any other valid restriction

#### Scenario: The expiration job is delayed
- **WHEN** a worker requests work at or after the recorded invalidation time before the job runs
- **THEN** the missed refresh is detectable and repair is requested, while admission evaluates the latest completed inputs without a temporary pause

#### Scenario: A key correction concerns an old response
- **WHEN** correction occurs after that response's submission time has left the current window
- **THEN** history is repaired without making the old response recent or extending its enforcement lifetime
