## Purpose

Give organizations explainable worker-quality evidence and recoverable control over future project work while preserving submitted answers, existing attempts, and organization privacy.

## ADDED Requirements

### Requirement: Scoped assessments preserve evidence and uncertainty
Reputation SHALL assess the existing global User at project, organization, and platform-controlled global scope. Assessments SHALL distinguish known-answer correctness, substantive human review, peer agreement, reliability, and experience, and expose contributing counts, the evidence window, and calculation provenance to authorized readers. Insufficient history SHALL be represented as unknown or provisional rather than poor quality or established excellence. Global calculations SHALL use platform-defined eligible evidence and SHALL NOT average scores calculated under different local settings. One organization's settings SHALL NOT change another organization's assessment or the global calculation.

#### Scenario: A new worker has insufficient history
- **WHEN** the worker has fewer observations than the configured minimum for a signal
- **THEN** that signal is provisional or unknown with its actual count, without a fabricated success or failure score

#### Scenario: Organizations use different settings
- **WHEN** two organizations give the same worker different local assessments
- **THEN** each assessment retains its scope and provenance, and neither local score overwrites the other or becomes an unqualified global average

### Requirement: Review and task facts retain their meaning
Assessments SHALL derive from authoritative submitted answers, attempts, known-answer keys, and review evidence. Automatic acceptance of submitted answers SHALL NOT count as independent evidence of correctness. Human-review evidence SHALL retain its effective verdict and provenance; a rejection SHALL NOT be treated as an answer key. Skips SHALL remain distinguishable and SHALL NOT automatically reduce quality. Reputation SHALL NOT rewrite worker answers, issue review verdicts, select canonical answers, change submission targets, create replacement demand, or reopen satisfied tasks.

#### Scenario: Automatic review accepts every answer
- **WHEN** an automatically reviewed project accepts a worker's submissions
- **THEN** those acceptances do not increase substantive human-review quality or substitute for known-answer grading

#### Scenario: A quality concern follows task completion
- **WHEN** reputation detects repeated disagreement after a task reaches its submission target
- **THEN** the task stays satisfied and its responses, review verdicts, and sealed exports remain unchanged

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

### Requirement: Known-answer evidence reflects actual worker exposure
A known-answer check SHALL mean a question with an organization-supplied expected answer for its exact task inputs. Such questions SHALL follow ordinary task allocation and submission capacity; this release SHALL NOT guarantee a check frequency or minimum number of checks for each worker. Authorized assessment reads SHALL report each worker's actual evaluated known-answer count, its configured minimum, and whether that minimum is met. Skipped, disabled, and exposure-excluded checks SHALL NOT count as evaluated successes or failures. Exhaustion of authored checks or insufficient observations SHALL leave the signal unknown/provisional and SHALL NOT itself trigger a poor-quality suspension. This SHALL NOT bypass a separately configured admission requirement for established evidence. Reports SHALL NOT imply that every worker was tested merely because the project contains known-answer questions.

#### Scenario: Earlier workers consume the available known-answer tasks
- **WHEN** ordinary allocation satisfies those tasks before another worker encounters them
- **THEN** the later worker's known-answer count remains zero and the signal is unknown, without a fabricated score or a failure-based suspension

#### Scenario: A worker sees questions but does not produce evaluable answers
- **WHEN** a worker skips known-answer questions or their evaluations are excluded
- **THEN** those observations do not satisfy the evaluated-answer minimum and the assessment reports the actual eligible count

### Requirement: Keys and check designations remain private
Worker presentation SHALL use the ordinary question/input contract without disclosing the answer key or the designation of a question as a quality check. Worker-facing APIs, nested GraphQL traversal, errors, and work-access outcomes SHALL NOT reveal hidden keys, other workers' answers, or another organization's private evidence. A worker account SHALL NOT gain manager access by holding an attempt. Authorized organization reviewers SHALL be able to inspect only the supporting evidence permitted by their scoped authority. Detailed worker-facing reputation explanations and dispute workflows are deferred; organization reviewer evidence and recovery actions remain in scope.

#### Scenario: An external worker inspects a work bundle
- **WHEN** an eligible external worker reads a task containing a known-answer check
- **THEN** ordinary task content is available without organization membership, while check designation, key, and manager-only relationships remain inaccessible

#### Scenario: A worker follows nested relationships
- **WHEN** a worker requests key data or other workers' answers through an attempt, task, question, or assessment relationship
- **THEN** the request grants no access to that protected evidence

### Requirement: Prior key exposure cannot manufacture quality evidence
The system SHALL retain attributable key authorship and the first platform disclosure of each check's key to each user. An answer submitted by a key author, or by a user to whom that key was disclosed before or during submission, SHALL be excluded from quality reputation evidence for that check in every assessment scope. It SHALL also be excluded from peer comparisons as either the assessed answer or a peer vote. Revoking management permissions or correcting the key SHALL NOT erase prior exposure. A later authorized disclosure SHALL NOT invalidate an already-submitted blind answer solely because it occurred later. Creating, correcting, or disabling a key SHALL be denied when the acting user has already submitted an answer to that exact task/question; another authorized actor must perform the change. Disclosure and submission SHALL have a consistent transactional order so concurrent reads cannot create apparently blind evidence. Source answers, reviewability, and collection counts SHALL remain unchanged.

#### Scenario: An author later performs the work
- **WHEN** a key author submits an answer to the corresponding question
- **THEN** collection retains the answer but it earns no quality reputation evidence from that check, including through a subsequent human review

#### Scenario: Key access is revoked before work
- **WHEN** a user has already retrieved a key and later answers the question after losing key access
- **THEN** the retained disclosure still excludes that answer from the relevant quality evidence

#### Scenario: A manager attempts to grade their own prior answer
- **WHEN** a user tries to create, correct, or disable a key for a task/question they have answered
- **THEN** the action fails without changing the key or assessment; another authorized actor can perform a legitimate correction

#### Scenario: Disclosure races submission
- **WHEN** a worker's submission competes with an authorized read of the corresponding key
- **THEN** the ordering either records prior exposure and excludes the answer, or establishes that submission preceded disclosure; permission changes cannot erase that ordering

### Requirement: Key corrections preserve history and repair assessments
Authorized corrections or disabling a faulty key SHALL retain the prior key, matching rule, actor, reason, and evaluation provenance. Correcting keys SHALL NOT mutate submitted answers. A correction SHALL cause affected assessments and reputation restrictions to be reevaluated under the repaired evidence; obsolete evaluations SHALL NOT remain effective after recalculation or overwrite a newer result. Review corrections SHALL likewise feed recalculation. Reviewers SHALL have evidence to identify widespread key failures and investigate potentially incorrect keys or instructions.

#### Scenario: A wrong expected answer penalizes workers
- **WHEN** an authorized manager corrects or disables that key
- **THEN** its old evaluation remains explainable, affected assessments are recalculated, and restrictions based on the faulty evidence are reevaluated without editing submissions

#### Scenario: A stale recalculation finishes later
- **WHEN** a calculation using an older key or review finishes after a calculation using its correction
- **THEN** it cannot restore the obsolete assessment or restriction

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
Peer comparisons SHALL become eligible for reputation scoring and enforcement only when the task reaches its frozen submission target and the final distinct-peer sample satisfies the configured minimum and consensus threshold. Earlier comparisons SHALL be labeled provisional and available only as authorized reviewer information; they SHALL NOT contribute to scores or admission/restriction decisions. Completing a project before a task meets its target SHALL NOT convert that partial comparison into enforceable evidence. A current assessment containing pending comparisons SHALL remain distinguishable from a stale calculation; unfinished evidence alone SHALL NOT cause indefinite allocation retries. Existing insufficient-history admission rules SHALL still apply.

#### Scenario: An early majority reverses
- **WHEN** early submitted answers favor one option but the final submitted set favors another
- **THEN** the early comparison causes no score change or suspension, and only the completed eligible comparison contributes

#### Scenario: A project closes with a partially answered task
- **WHEN** completion cancels remaining capacity before the task's submission target is met
- **THEN** its peer comparison remains non-enforcing and collection is not reopened to obtain more answers

### Requirement: Signal actions support review and recoverable project suspension
Each enabled signal SHALL support a configured action to inform reviewers or suspend new project work after its minimum evidence and threshold conditions are met. Its enforcement action SHALL be distinct from its scoring contribution. Known-answer failures SHALL support automatic suspension. Disagreement SHALL default to informing reviewers and SHALL require explicit project opt-in for automatic suspension. Automatic restrictions SHALL be project-scoped and SHALL NOT impose platform-wide account bans. Authorized reviewers SHALL receive the reason and supporting evidence; authorized managers SHALL be able to reinstate a worker without changing the underlying answers or fabricating a score adjustment. Reinstatement and recalculation SHALL have attributable, repeatable outcomes.

#### Scenario: Known-answer failures cross an enforced threshold
- **WHEN** enough evaluated checks establish failure under a project's configured automatic action
- **THEN** the worker is suspended from new work in that project with a reason inspectable by authorized organization reviewers

#### Scenario: Repeated disagreement uses the default action
- **WHEN** disagreement exceeds its threshold without explicit automatic-suspension opt-in
- **THEN** authorized reviewers receive the concern while the concern alone does not suspend the worker

#### Scenario: A reviewer reinstates a worker
- **WHEN** an actor with reinstatement authority acts on a project restriction
- **THEN** the action records its reason and effect without granting access in another project or changing historical task evidence

### Requirement: Reputation operations fail closed within organization scope
Organization settings, keys, assessments, reviewer information, and restriction management SHALL require explicit organization scope and operation-appropriate management or review authority. Organization management SHALL require an active authenticated account, active organization, active membership, and explicit capability grants. Foreign and nonexistent targets SHALL fail without distinguishable disclosure. Worker sessions SHALL require an account while retaining existing optional-membership audience routes. Platform-controlled global summaries SHALL NOT disclose other organizations' raw evidence or grant management access.

#### Scenario: A reviewer supplies another organization's assessment
- **WHEN** an otherwise authorized reviewer substitutes a foreign organization, project, worker assessment, or key reference
- **THEN** the operation discloses and changes no unauthorized record

#### Scenario: Management authority is revoked
- **WHEN** a manager loses the required capability or active membership before a mutation commits
- **THEN** the mutation fails closed without partial changes

### Requirement: Recalculation is reproducible and safe to repeat
Assessments SHALL be rebuildable from retained authoritative evidence and the applicable scoped configuration. Equivalent evidence and calculation inputs SHALL yield equivalent assessments. Repeated calculation, submission retries, key corrections, and review retries SHALL NOT double-count evidence or duplicate restriction effects. Readers SHALL be able to distinguish a pending recalculation from a current assessment. New-work admission SHALL NOT silently use an assessment known to be stale when that assessment determines access; it SHALL obtain a current decision or return a retryable outcome.

#### Scenario: A rebuild runs twice
- **WHEN** the same evidence and configuration are evaluated again
- **THEN** scores, counts, and effective restriction outcomes converge without duplicate penalties

#### Scenario: Admission needs an assessment under repair
- **WHEN** corrected evidence makes the access decision stale before a worker fetches new work
- **THEN** allocation obtains a current decision or returns a retryable outcome without issuing work based on the known-stale result

### Requirement: Time windows expire evidence without requiring a new submission
Each time-windowed assessment SHALL record its evaluation cutoff and next time-dependent invalidation, if any. Answer-derived observations SHALL be dated by the original answer's submission time; other time-windowed evidence SHALL use its signal's original event timestamp rather than job time. Key correction, delayed peer completion, and review correction SHALL NOT restart an observation's age. For duration W at cutoff T, eligible observations SHALL have original event times greater than T minus W and no later than T. The next invalidation SHALL be no later than the earliest included observation's original event time plus W. At or after that boundary, reads SHALL identify the cached assessment as stale and new-work admission SHALL refresh it or return a retryable result, even if no evidence write or background job has occurred. Scheduled recalculation SHALL reevaluate the assessment and its automatic restrictions. An expired failure-based reason SHALL cease to suspend once its current threshold or minimum-evidence condition is no longer met; other active reasons, explicit blocks, and separate established-evidence admission requirements SHALL remain effective. Insufficient remaining history SHALL become unknown/provisional, never a success score.

#### Scenario: A suspended worker produces no new answers
- **WHEN** the evidence supporting an automatic suspension expires out of the window
- **THEN** time-driven recalculation or the next access decision reevaluates it without requiring a new submission, removing the unsupported reason while retaining any other valid restriction

#### Scenario: The expiration job is delayed
- **WHEN** a worker requests work at or after the recorded invalidation time before the job runs
- **THEN** admission refreshes the assessment or returns a retryable result instead of treating the expired score as current

#### Scenario: A key correction concerns an old response
- **WHEN** correction occurs after that response's submission time has left the current window
- **THEN** history is repaired without making the old response recent or extending its enforcement lifetime
