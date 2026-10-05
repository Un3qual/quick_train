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

### Requirement: Keys and check designations remain private
Worker presentation SHALL use the ordinary question/input contract without disclosing the answer key or the designation of a question as a quality check. Worker-facing APIs, nested GraphQL traversal, errors, and reputation explanations SHALL NOT reveal hidden keys, other workers' answers, or another organization's private evidence. A worker account SHALL NOT gain manager access by holding an attempt. Authorized organization reviewers SHALL be able to inspect only the supporting evidence permitted by their scoped authority.

#### Scenario: An external worker inspects a work bundle
- **WHEN** an eligible external worker reads a task containing a known-answer check
- **THEN** ordinary task content is available without organization membership, while check designation, key, and manager-only relationships remain inaccessible

#### Scenario: A worker follows nested relationships
- **WHEN** a worker requests key data or other workers' answers through an attempt, task, question, or assessment relationship
- **THEN** the request grants no access to that protected evidence

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

### Requirement: Signal actions support review and recoverable project suspension
Each enabled signal SHALL support a configured action to inform reviewers or suspend new project work after its minimum evidence and threshold conditions are met. Its enforcement action SHALL be distinct from its scoring contribution. Known-answer failures SHALL support automatic suspension. Disagreement SHALL default to informing reviewers and SHALL require explicit project opt-in for automatic suspension. Automatic restrictions SHALL be project-scoped and SHALL NOT impose platform-wide account bans. Authorized reviewers SHALL receive the reason and supporting evidence; authorized managers SHALL be able to reinstate a worker without changing the underlying answers or fabricating a score adjustment. Reinstatement and recalculation SHALL have attributable, repeatable outcomes.

#### Scenario: Known-answer failures cross an enforced threshold
- **WHEN** enough evaluated checks establish failure under a project's configured automatic action
- **THEN** the worker is suspended from new work in that project with an inspectable reason

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
