## MODIFIED Requirements

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze authored tasks and inputs, bindings, slot counts/order policy, audience/external-access mode, review mode, submission target, project-wide skip rules, lease duration, and effective reputation configuration. Dataset/schema/form identities SHALL be immutable from creation, including in draft. Peer eligibility SHALL honor the questions' immutable participation values in the pinned published form version, without a project-level question override or copying a second mutable flag map. Each task SHALL require the project's positive `submission_target` (default 1, maximum 2,147,483,647). `skip_allowed` and `reason_required` SHALL default to false and apply to the whole form. Review SHALL be automatic or manual; leases SHALL be 1–120 minutes with a 30-minute default. Tasks and TaskInputs SHALL exist as draft configuration before activation. Activation SHALL validate existing known-answer keys against the final authored task/question/input contracts and freeze their check designations; new keys SHALL be created only while the owning project is draft. Activation SHALL create no attempts, coverage rows, or progress projections. Child edits, initial key creation, and activation SHALL serialize under the Project lock. After activation only title, lifecycle, and per-user allow/block overrides SHALL be editable as ordinary project configuration. Scoped known-answer corrections, disabling/re-enabling existing keys, return classification/corrections, and reputation reinstatement SHALL remain available through their dedicated authorized operations without reopening the frozen collection configuration or introducing a new check designation.

#### Scenario: A draft edit races activation
- **WHEN** task authoring or policy editing competes with activation
- **THEN** the complete edit is either included in activation validation or rejected after freezing

#### Scenario: An import arrives after activation
- **WHEN** a later revision is imported
- **THEN** the frozen cohort and all issued inputs remain unchanged

#### Scenario: A manager changes worker access
- **WHEN** an authorized manager edits an active project's per-user override
- **THEN** the edit rechecks current management authority under the Project lock without reopening configuration

#### Scenario: A key is corrected after activation
- **WHEN** an authorized manager corrects a known-answer key
- **THEN** retained key history and reputation are updated through the correction workflow while published questions, task inputs, submission targets, and frozen scoring settings stay unchanged

#### Scenario: An existing key is re-enabled after activation
- **WHEN** an authorized manager explicitly re-enables an existing corrected key
- **THEN** its retained history and reputation are updated through the key workflow without reopening frozen collection configuration

## ADDED Requirements

### Requirement: Organization defaults resolve into explicit project reputation settings
Reputation configuration SHALL support organization defaults and draft-project overrides using a bounded set of typed settings: enabled signals, minimum worker samples, peer count floor and coverage fraction, consensus thresholds and numeric tolerance, one observation-based EWMA half-life, admission thresholds, evidence scope and each performance rule's lifetime/EWMA basis, and each signal's enforcement action. Score weights SHALL come from the central application definition, not organization/project overrides, and activation SHALL retain their effective values with the frozen configuration. Configuration management SHALL use explicit organization scope, active account/organization/membership, and the existing `projects.manage` capability under the [operation mapping](../worker-reputation/spec.md#requirement-reputation-operations-fail-closed-within-organization-scope); foreign references SHALL fail closed. Project settings SHALL resolve atomically at activation into one complete effective configuration. Later organization-default or application-default weight changes SHALL NOT silently change an active project's scoring or enforcement rules. Customer-authored formulas and weight overrides SHALL NOT be accepted. A combined answer-quality admission requirement SHALL select at least one enabled known-answer correctness, substantive human-review, or peer-agreement signal configured for automatic access decisions. Reliability and experience SHALL remain separate inputs for their own permitted rules and SHALL NOT be accepted as combined-score contributors. Disabled and reviewer-only signals SHALL NOT contribute to its value or count as missing evidence. Organization/global entry requirements SHALL obey the same signal selection without changing those independent assessments. Invalid combinations or unsupported grading contracts, including gates using aggregates with excluded contributors, SHALL fail activation without partially freezing the project.

Initial project defaults SHALL use minimum worker samples of twenty for known-answer correctness, twenty for substantive human review when selected, and thirty for peer agreement under the [effective-sample contract](../worker-reputation/spec.md#requirement-evidence-minimums-account-for-ewma-weight-concentration). Lifetime uses actual counts and EWMA uses effective sample size independently per signal. Peer minima SHALL NOT mean that many other workers per question; each comparison still requires its own distinct-peer and consensus safeguards. Each scope SHALL provide both views with an initial EWMA half-life of one hundred newer eligible observations and no hard history cap. Authorized organization defaults and draft-project overrides SHALL be able to change minima and half-life through typed validation and activation freezing; customer contributor-weight overrides SHALL remain unsupported. Human-review scoring SHALL remain unselected by default. Organization/global assessments SHALL retain their own explicit scoped defaults rather than inherit source-project settings. Draft or frozen project overrides SHALL NOT reconfigure broader assessments. Organization-default edits SHALL refresh the organization's own assessment without changing active project contracts or global settings. A source project's frozen agreement-scoring selection SHALL determine whether its comparisons supply scored peer evidence in any scope; reviewer-only action SHALL remain distinct from disabled scoring. These defaults SHALL NOT silently change existing active projects.

Peer settings SHALL initially use a count floor of two, an eighty-percent coverage fraction applied to the source task's frozen target minus one with rounding up, and a separate eighty-percent consensus threshold over all eligible actual other answers, as defined by the [peer-comparison contract](../worker-reputation/spec.md#requirement-peer-comparison-requires-sufficient-comparable-evidence). Activation SHALL validate and retain these effective values with the frozen project configuration. Authorized defaults/draft overrides SHALL be able to adjust the bounded peer parameters independently; changing coverage SHALL NOT implicitly change consensus or the worker's separate comparison minimum. The peer count floor SHALL be an integer of at least two, and coverage SHALL be positive and no greater than one. Consensus SHALL be a finite percentage greater than fifty and no greater than one hundred, independently of the worker agreement action threshold.

Numeric peer tolerance SHALL be an absolute, finite, nonnegative numeric distance, initially zero for exact matching, under the [typed matching contract](../worker-reputation/spec.md#requirement-supported-answer-matching-uses-typed-values). Activation SHALL validate and freeze its effective value; it SHALL NOT inherit a known-answer key's tolerance or reconfigure another assessment scope. Scoped keys SHALL retain their own authored tolerance through the existing key-authoring and correction contract.

Reliability SHALL initially use minimum twenty independently in each view under the [reliability](../worker-reputation/spec.md#requirement-reliability-includes-unexcused-returns-and-excludes-legitimate-returns) and effective-sample contracts, using only eligible completions, expirations and unexcused returns. The positive-integer minimum SHALL be adjustable through authorized defaults/draft overrides, validated against the chosen basis's attainable evidence, and frozen at activation. Organization/global assessments SHALL retain explicit initial minimum twenty under their own settings. Excused/awaiting-review returns, cancellations and unstarted direct assignments SHALL satisfy neither view's minimum or advance its decay ranking.

The EWMA half-life SHALL be a positive integer from one through 2,147,483,647, initially one hundred newer eligible observations, with one resolved value shared by the scope's performance signals and independent eligible ordering for each signal. Authorized organization settings/draft overrides SHALL be able to adjust it using the existing precedence and activation-freezing contract. Global configuration SHALL remain platform-controlled. Lifetime SHALL retain equal-weight eligible history without a configurable cutoff. Each performance rule SHALL resolve and freeze a lifetime/EWMA history basis, defaulting to EWMA; a combined rule SHALL use one basis for all contributors. Experience SHALL remain an all-history submitted-question count. Hard count windows, elapsed-time windows/decay and multiple overlapping weighted periods SHALL NOT be supported in this change. A project rule consulting organization/global evidence SHALL use that assessment's retained half-life rather than the target project's local one.

Percentage action/admission thresholds SHALL be finite values from zero through one hundred inclusive and follow the [inclusive-minimum comparison contract](../worker-reputation/spec.md#requirement-reputation-thresholds-use-inclusive-minimums), using the unrounded rate/score after evidence establishment. Initial configured rules SHALL use the [starting threshold contract](../worker-reputation/spec.md#requirement-configured-rules-have-explicit-starting-thresholds): ninety percent known-answer correctness, ninety percent substantive human-review acceptance when selected, eighty percent worker peer agreement, ninety percent combined answer quality, and ninety-four percent reliability. Authorized organization defaults and draft-project overrides SHALL be able to adjust these values independently through the existing resolution and activation-freezing contract. These values SHALL also supply starting thresholds for explicitly configured project entry rules that consult organization/global evidence, without changing those assessments' calculation settings. Experience SHALL have no default entry gate; an explicit organization/global experience requirement SHALL use a positive integer all-history answered-question minimum, without applying EWMA effective-sample limits or the target project's local evidence maxima. Invalid values SHALL fail activation without partially freezing configuration. Equality SHALL meet an at-least requirement; selection, reviewer-only exclusions, and the project's existing insufficient-history behavior SHALL remain effective. Setting a threshold SHALL NOT silently enable an automatic action, select human-review scoring, or reconfigure independent organization/global assessments. Existing active projects SHALL retain their frozen contracts.

#### Scenario: A project overrides organization defaults
- **WHEN** a draft project overrides the disagreement action and then activates
- **THEN** activation freezes that explicit action together with the resolved remaining defaults

#### Scenario: A draft overrides one starting action threshold
- **WHEN** an organization uses the initial ninety-percent correctness threshold and an authorized draft-project override chooses eighty-five percent
- **THEN** activation freezes eighty-five percent for that project's configured correctness rule while other thresholds resolve independently; existing active projects and independent organization/global calculations remain unchanged

#### Scenario: Organization defaults change later
- **WHEN** an authorized manager edits defaults after a project activates
- **THEN** the active project's effective settings remain unchanged while later activations can use the revised defaults

#### Scenario: A project overrides its reliability minimum
- **WHEN** an authorized draft override sets the reliability minimum to twenty-five while organization and global minima remain at their initial twenty
- **THEN** activation validates and freezes twenty-five for that project without changing either broader assessment's minimum or counting excluded outcomes toward it

#### Scenario: Defaults change concurrently with activation
- **WHEN** a defaults update races project activation
- **THEN** activation uses one coherent configuration from before or after the update rather than a mixture

#### Scenario: A project requests unsupported scoring
- **WHEN** activation encounters invalid comparison settings, an unsupported grading family, or customer-provided weight overrides
- **THEN** it returns scoped validation issues and leaves the project editable in draft

#### Scenario: Admission requires a combined score with no eligible contributors
- **WHEN** draft configuration requires a combined answer-quality score but selects no eligible quality signals configured for automatic access decisions, including when all quality signals are reviewer-only or only reliability/experience is selected
- **THEN** activation rejects the unusable requirement rather than producing permanently insufficient admission evidence or a fabricated passing score

#### Scenario: Human review is omitted by default
- **WHEN** a project activates without an explicit organization-default or draft-project selection of human-review scoring
- **THEN** its frozen configuration excludes human review from the combined quality score and its minimum-evidence requirements, while existing human review decisions remain retained

#### Scenario: An organization explicitly includes human review
- **WHEN** an authorized organization default or draft-project override selects human review as a quality contributor
- **THEN** activation freezes that selection and its minimum alongside the other effective settings, without requiring a review quota or later removing that contribution merely because reviews are sparse

#### Scenario: Initial project evidence defaults are frozen
- **WHEN** an otherwise valid draft activates without overriding the initial worker minima, half-life or rule history basis
- **THEN** its frozen settings retain the twenty/twenty/thirty quality minima, reliability minimum twenty, half-life one hundred and EWMA default rule basis, with human review unselected and its minimum inactive unless selected

#### Scenario: A rule explicitly selects lifetime
- **WHEN** an otherwise valid draft explicitly chooses lifetime for an organization known-answer entry rule
- **THEN** activation freezes lifetime for that rule, retaining the separately reported EWMA view and ordinary defaults for other rules

#### Scenario: A project selects a different half-life
- **WHEN** authorized organization defaults or a draft override choose half-life fifty with attainable automatic evidence minima
- **THEN** activation freezes that half-life and the chosen bases, preserving application-owned contributor weights and independent broader assessment settings

#### Scenario: A configured half-life takes precedence over the starting value
- **WHEN** applicable organization defaults choose half-life fifty and an otherwise valid draft has no half-life override
- **THEN** activation freezes the inherited half-life fifty rather than the starting one hundred

#### Scenario: Initial peer parameters scale with the source target
- **WHEN** a draft project with submission target ten activates under the initial peer defaults
- **THEN** its frozen configuration retains a floor of two, eighty-percent coverage, and eighty-percent consensus, requiring eight eligible other answers before testing agreement among all eligible peers

#### Scenario: A coverage override leaves consensus independent
- **WHEN** an authorized draft override changes peer coverage while keeping the initial consensus and worker comparison minimum
- **THEN** activation retains that coverage override alongside eighty-percent consensus and the thirty-comparison worker minimum without changing either automatically

#### Scenario: A consensus override cannot permit competing minorities
- **WHEN** configuration supplies a consensus percentage at or below fifty, above one hundred, or a nonfinite value
- **THEN** the invalid value is rejected without partial configuration changes or activation; one hundred remains a valid unanimity requirement

### Requirement: Activation identifies impossible project-local evidence settings
For reputation rules using only this project's evidence, activation SHALL compare each automatic rule's minimum, including every required combined-quality contributor's minimum, with the maximum attainable sample size under its chosen basis. Ordinary allocation permits at most one attempt per worker/task. The raw maximum N SHALL be the enabled scoreable keyed task/question count for known answers, reviewable answered-question count for human review, supported unkeyed included task/question count for peer agreement, and authored task count for reliability. Disabled designated checks and questions excluded by the pinned form version SHALL remain excluded from the peer maximum. Question exclusion SHALL NOT reduce the task's submission target or the included questions' other-worker coverage denominator. Lifetime capacity SHALL be N; EWMA capacity SHALL be the finite effective sample size at N under the [sample-sufficiency contract](../worker-reputation/spec.md#requirement-evidence-minimums-account-for-ewma-weight-concentration), not its raw count or infinite-history limit. These maxima SHALL assume all eligible work is encountered and answered, without guaranteeing distribution, review, consensus or eligible outcomes. An unattainable automatic minimum SHALL fail activation; an unattainable reviewer-only minimum SHALL produce an advisory. Explain the signal, basis, required minimum, raw maximum and effective capacity without simulating allocation.

Activation SHALL validate organization/global rules against their independently resolved broader settings and applicable evidence minimum, without using the target project's finite local maxima. An automatic EWMA minimum at or above that scope's strict infinite-history effective-size limit SHALL be rejected; lifetime and experience requirements SHALL not acquire that decay bound. Effective signal selection and every selected combined contributor SHALL remain valid for the declared scope. A project-local automatic peer rule SHALL also reject an other-worker minimum `max(peer_floor, ceil(peer_coverage_fraction * (submission_target - 1)))` greater than `submission_target - 1`, including targets one/two under the initial floor. Impossible reviewer-only requirements SHALL produce advisories. Validation SHALL NOT silently adjust half-life, minima, source selection or submission targets.

When known-answer scoring/enforcement is enabled, activation SHALL advise that ordinary shared task capacity may leave individual workers with fewer observations, including none. A feasible theoretical capacity SHALL not guarantee established reputation, reserve checks, create qualification attempts, change submission targets or reopen collection.

#### Scenario: Question exclusions reduce attainable peer evidence
- **WHEN** a draft with submission target three has forty supported unkeyed task/question contracts but its pinned form excludes twenty of them from peer scoring, and a project-local automatic lifetime peer rule requires thirty comparisons
- **THEN** activation rejects the unattainable minimum using the twenty included contracts; the same reviewer-only rule produces an advisory, and excluded answers retain their ordinary collection and experience behavior

#### Scenario: A project cannot supply its own configured minimum
- **WHEN** local automatic lifetime correctness requires ten observations but the project contains only four enabled scoreable checks
- **THEN** activation fails with the four-versus-ten explanation and leaves the project draft

#### Scenario: Finite EWMA capacity differs from the raw count
- **WHEN** twenty scoreable checks are authored and automatic EWMA correctness requires twenty effective observations at half-life one hundred
- **THEN** activation rejects the approximately 19.968 effective capacity despite twenty raw checks; explicitly choosing lifetime permits that evidence bound

#### Scenario: One more authored observation makes the default EWMA minimum feasible
- **WHEN** twenty-one scoreable checks are authored and automatic EWMA correctness requires twenty at half-life one hundred
- **THEN** its approximately 20.963 finite effective capacity passes that bound, without guaranteeing actual delivery or evaluability

#### Scenario: Too few tasks can establish an automatic reliability rule
- **WHEN** five tasks are authored and a project-local automatic reliability rule requires twenty under either history basis
- **THEN** activation fails with the scoped raw/effective capacity explanation without allowing repeated attempts at the same task

#### Scenario: Peer coverage is possible but worker history is not
- **WHEN** five tasks each have two supported unkeyed questions, peer coverage is possible, and an automatic agreement rule requires thirty
- **THEN** activation fails because ten raw comparisons cannot establish either basis, independently of peers per question

#### Scenario: A selected human-review contributor has an impossible minimum
- **WHEN** work supplies at most six reviewable answered questions and an automatic combined rule requires twenty human-review observations
- **THEN** activation rejects the selected basis's insufficient capacity without assuming more tasks, repeat attempts or a review quota

#### Scenario: A fast decay cannot satisfy a broader automatic minimum
- **WHEN** an organization/global EWMA entry rule requires thirty effective observations under half-life ten
- **THEN** activation rejects the approximately 28.865 infinite limit; the target project's local work quantity is irrelevant

#### Scenario: Experience entry requirements are independent of decay
- **WHEN** a draft requires one hundred fifty eligible organization submitted answered questions while organization half-life is fifty
- **THEN** activation compares that experience requirement to the all-history count without imposing an EWMA capacity bound

#### Scenario: A lifetime entry minimum is independent of decay
- **WHEN** a draft requires eighty lifetime organization known-answer observations while organization half-life is ten and correctness remains enabled
- **THEN** that lifetime count requirement is not rejected for the EWMA limit, and actual lifetime performance is evaluated at admission

#### Scenario: A peer rule requires more other workers than the task can supply
- **WHEN** a local automatic peer rule requires three other workers but the submission target is three
- **THEN** activation fails because only two other workers are possible, without increasing the target

#### Scenario: A small target cannot meet the default peer floor
- **WHEN** target two uses the initial two-peer floor for a local automatic peer rule
- **THEN** activation rejects the rule; a reviewer-only version instead receives an advisory without manufactured peers or a changed target

#### Scenario: Only reviewer information has an impossible minimum
- **WHEN** reviewer-only agreement requires thirty effective observations at half-life ten and no automatic requirement depends on it
- **THEN** activation advises that its effective limit is approximately 28.865 without failing solely for that informational minimum or fabricating an established score

#### Scenario: Equality meets a finite evidence bound
- **WHEN** a lifetime automatic rule requires exactly its authored raw maximum and peer coverage requires exactly the available other-worker capacity
- **THEN** those checks pass, while actual evidence and consensus still determine usable reputation

#### Scenario: Prior peer evidence comes from other projects
- **WHEN** a project entry rule uses eligible global peer evidence but its own submission target is one
- **THEN** activation validates the global basis/settings instead of rejecting the broader rule for a lack of local peers

### Requirement: Broader setting edits preserve feasible frozen entry requirements
Mutable organization/global settings changes SHALL preserve the static feasibility of automatic entry requirements in already-frozen active projects consulting that scope. An edit SHALL fail without partial settings changes if it disables a required contributor or makes a required EWMA minimum unattainable, accounting for both the assessment minimum and the rule's declared minimum. Lifetime requirements SHALL not acquire an EWMA capacity limit, and reviewer-only impossible requirements SHALL retain advisory behavior. Valid changes SHALL refresh the broader assessment under its existing revision guard without rewriting frozen project rules or historical assessments. Activation and broader settings edits SHALL serialize the feasibility check so a concurrent new frozen requirement cannot be omitted. This is static configuration validation, not a guarantee of actual eligible worker evidence or a prohibition on authorized source corrections.

#### Scenario: A shorter half-life would strand an active entry rule
- **WHEN** an active project requires eighty effective organization EWMA observations and an organization edit proposes half-life ten
- **THEN** the edit is rejected because its approximately 28.865 limit cannot satisfy that frozen rule, retaining the previous settings

#### Scenario: A lifetime requirement permits an otherwise valid half-life change
- **WHEN** an active project requires eighty lifetime organization known-answer observations and an otherwise valid edit changes half-life to ten
- **THEN** that lifetime count requirement does not block the change solely for EWMA capacity, while other required contributors and automatic rules remain checked

#### Scenario: Activation races a broader settings edit
- **WHEN** a new broader entry rule is frozen concurrently with a settings edit
- **THEN** the serialized operations validate one coherent configuration and retain no structurally impossible automatic requirement

### Requirement: Reputation admission provides a path to initial project evidence
Admission rules SHALL declare their evidence scope, lifetime/EWMA performance basis and minimum; experience uses its separate all-history count basis. A project-local rule SHALL permit otherwise-eligible workers to participate while its local evidence is insufficient; its threshold SHALL apply once its minimum is met. Activation SHALL reject a project-only established-history requirement that denies insufficient local history. Projects requiring established reputation before the first task SHALL use eligible organization/global evidence that can be earned outside the target project. Genuinely missing broader evidence MAY deny admission when that requirement is explicitly configured. Each new work request SHALL evaluate the latest completed inputs in the required scopes; an earlier denial SHALL remain historical and SHALL NOT require separate project recalculation or manual clearance after broader reputation improves. An unprocessed initial assessment SHALL NOT be treated as missing evidence or require a queued-job wait; the ordinary admission request SHALL prepare it outside allocation locks when no completed assessment exists, then revalidate under those locks before issuance. Participation with insufficient local evidence SHALL NOT bypass account/audience restrictions, another rule whose failure conditions are met, or a separately configured organization/global entry requirement. This SHALL use the existing assessment and allocation lifecycle without introducing qualification attempts or guaranteeing known-answer delivery.

#### Scenario: A new worker starts a project-local assessment
- **WHEN** an otherwise eligible worker has insufficient local evidence and satisfies any configured organization/global entry requirement
- **THEN** the local rule permits participation without fabricating a passing score, and begins applying its threshold once enough evidence exists

#### Scenario: A project requires its own history before collecting any
- **WHEN** draft configuration denies entry to workers lacking established history from that same project
- **THEN** activation fails with a scoped explanation that the rule must allow local participation with insufficient evidence or use organization/global entry evidence

#### Scenario: An experienced worker qualifies from other projects
- **WHEN** a worker with no target-project history satisfies its established organization/global reputation requirement using eligible prior work
- **THEN** that requirement permits entry without demanding prior work in the target project

#### Scenario: A worker lacks required broader history
- **WHEN** a project explicitly requires established organization/global reputation and the worker has insufficient evidence in that scope
- **THEN** admission denies entry even though the local rule permits participation, leaving projects that admit newcomers as the route to earning broader history

#### Scenario: A previously denied worker qualifies later
- **WHEN** a worker earns enough eligible broader history elsewhere and its completed assessment satisfies the target project's entry rule
- **THEN** their next new-work request reevaluates admission with that assessment without waiting for a target-project refresh, while retaining the prior denial as history

### Requirement: Introducing reputation preserves existing active projects
Deploying reputation SHALL NOT silently enable new admission thresholds or automatic restrictions on projects already activated under the previous contract. Their frozen collection configuration and issued evidence SHALL be preserved. New reputation enforcement SHALL be selected through the activation contract rather than a migration that opts existing active projects into changed rules.

#### Scenario: Reputation is deployed while workers are active
- **WHEN** an existing active project has live attempts and submitted evidence
- **THEN** deployment preserves its existing admission behavior, attempt access, review history, and collection target
