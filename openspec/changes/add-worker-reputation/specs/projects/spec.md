## MODIFIED Requirements

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze authored tasks and inputs, bindings, slot counts/order policy, audience/external-access mode, review mode, submission target, project-wide skip rules, lease duration, and effective reputation configuration. Dataset/schema/form identities SHALL be immutable from creation, including in draft. Each task SHALL require the project's positive `submission_target` (default 1, maximum 2,147,483,647). `skip_allowed` and `reason_required` SHALL default to false and apply to the whole form. Review SHALL be automatic or manual; leases SHALL be 1–120 minutes with a 30-minute default. Tasks and TaskInputs SHALL exist as draft configuration before activation. Activation SHALL create no attempts, coverage rows, or progress projections. Child edits and activation SHALL serialize under the Project lock. After activation only title, lifecycle, and per-user allow/block overrides SHALL be editable as ordinary project configuration. Scoped known-answer corrections, disabling/re-enabling existing keys, return classification/corrections, and reputation reinstatement SHALL remain available through their dedicated authorized operations without reopening the frozen collection configuration.

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
Reputation configuration SHALL support organization defaults and draft-project overrides using a bounded set of typed settings: enabled signals, minimum worker samples, peer count floor and coverage fraction, consensus thresholds and numeric tolerance, recent-history window, admission thresholds and evidence scope, and each signal's enforcement action. Score weights SHALL come from the central application definition, not organization/project overrides, and activation SHALL retain their effective values with the frozen configuration. Configuration management SHALL use explicit organization scope, active account/organization/membership, and the existing `projects.manage` capability under the [operation mapping](../worker-reputation/spec.md#requirement-reputation-operations-fail-closed-within-organization-scope); foreign references SHALL fail closed. Project settings SHALL resolve atomically at activation into one complete effective configuration. Later organization-default or application-default weight changes SHALL NOT silently change an active project's scoring or enforcement rules. Customer-authored formulas and weight overrides SHALL NOT be accepted. A combined answer-quality admission requirement SHALL select at least one enabled known-answer correctness, substantive human-review, or peer-agreement signal configured for automatic access decisions. Reliability and experience SHALL remain separate inputs for their own permitted rules and SHALL NOT be accepted as combined-score contributors. Disabled and reviewer-only signals SHALL NOT contribute to its value or count as missing evidence. Organization/global entry requirements SHALL obey the same signal selection without changing those independent assessments. Invalid combinations or unsupported grading contracts, including gates using aggregates with excluded contributors, SHALL fail activation without partially freezing the project.

Initial project defaults SHALL use minimum worker samples of twenty evaluated known-answer answers, twenty substantive human-reviewed answers when that contributor is selected, and thirty eligible peer comparisons for the assessed worker. The peer worker minimum SHALL NOT mean thirty other workers per question; each comparison SHALL still satisfy its separate distinct-peer and consensus requirements. The default history window SHALL be count-based with at most one hundred eligible observations selected independently per signal. Authorized organization defaults and draft-project overrides SHALL be able to change those minima and the window through the existing typed settings, validation, and activation-freezing contract; customer weight overrides SHALL remain unsupported. Human-review scoring SHALL remain unselected by default. Organization/global assessments SHALL have their own explicit initial defaults under the [broader-assessment contract](../worker-reputation/spec.md#requirement-broader-assessments-pool-source-evidence-under-scoped-rules), even when their starting numerical values match project defaults. Draft or frozen project overrides SHALL NOT reconfigure those assessments. Organization-default edits SHALL refresh the organization's own assessment without changing active project contracts or global calculation settings. A source project's frozen agreement-scoring selection SHALL also determine whether its comparisons supply scored peer evidence in any scope; a reviewer-only action SHALL remain distinct from disabled scoring. These defaults SHALL NOT silently change existing active projects.

Peer settings SHALL initially use a count floor of two, an eighty-percent coverage fraction applied to the source task's frozen target minus one with rounding up, and a separate eighty-percent consensus threshold over all eligible actual other answers, as defined by the [peer-comparison contract](../worker-reputation/spec.md#requirement-peer-comparison-requires-sufficient-comparable-evidence). Activation SHALL validate and retain these effective values with the frozen project configuration. Authorized defaults/draft overrides SHALL be able to adjust the bounded peer parameters independently; changing coverage SHALL NOT implicitly change consensus or the worker's separate comparison minimum. The peer count floor SHALL be an integer of at least two, and coverage SHALL be positive and no greater than one.

Numeric peer tolerance SHALL be an absolute, finite, nonnegative numeric distance, initially zero for exact matching, under the [typed matching contract](../worker-reputation/spec.md#requirement-supported-answer-matching-uses-typed-values). Activation SHALL validate and freeze its effective value; it SHALL NOT inherit a known-answer key's tolerance or reconfigure another assessment scope. Scoped keys SHALL retain their own authored tolerance through the existing key-authoring and correction contract.

Reliability SHALL initially require twenty eligible task attempts in the assessed scope's selected history under the [reliability contract](../worker-reputation/spec.md#requirement-reliability-includes-unexcused-returns-and-excludes-legitimate-returns), using its completion/expiration/unexcused-return denominator rather than all observed attempts. The positive-integer minimum SHALL be adjustable through authorized organization defaults and draft-project overrides, validated against the applicable history bound, and frozen at project activation. Organization and global assessments SHALL each use an explicit initial minimum of twenty under their own settings; global settings SHALL remain platform-controlled, and project overrides SHALL NOT change broader minima. Excused returns, returns awaiting review, cancellations, and unstarted direct assignments SHALL NOT satisfy this minimum. The default count window SHALL remain one hundred eligible observations per signal.

Count-based history SHALL remain the initial mode with a limit of one hundred eligible observations per signal. The initial duration for optional time-based history SHALL be a positive elapsed-time duration of ninety days under the [time-window contract](../worker-reputation/spec.md#requirement-time-windows-expire-evidence-without-requiring-a-new-submission). Authorized organization settings and draft-project overrides SHALL be able to adjust that duration through the existing precedence: a draft override takes priority over its applicable organization default, with ninety days used when neither supplies a duration. Activation SHALL freeze the selected mode and its resolved count or duration, without combining the two limits. Organization and global assessments SHALL have their own explicit initial ninety-day duration when time mode is selected without a configured duration; global configuration SHALL remain platform-controlled. Choosing or overriding a project's time window SHALL NOT change broader settings or reopen active project contracts.

Percentage action/admission thresholds SHALL be finite values from zero through one hundred inclusive and follow the [inclusive-minimum comparison contract](../worker-reputation/spec.md#requirement-reputation-thresholds-use-inclusive-minimums), using the unrounded rate/score after evidence establishment. Initial configured rules SHALL use the [starting threshold contract](../worker-reputation/spec.md#requirement-configured-rules-have-explicit-starting-thresholds): ninety percent known-answer correctness, ninety percent substantive human-review acceptance when selected, eighty percent worker peer agreement, ninety percent combined answer quality, and ninety-five percent reliability. Authorized organization defaults and draft-project overrides SHALL be able to adjust these values independently through the existing resolution and activation-freezing contract. These values SHALL also supply starting thresholds for explicitly configured project entry rules that consult organization/global evidence, without changing those assessments' calculation settings. Experience SHALL have no default entry gate; an explicit experience requirement SHALL use a positive integer answered-question minimum and existing scoped feasibility checks. Invalid values SHALL fail activation without partially freezing configuration. Equality SHALL meet an at-least requirement; selection, reviewer-only exclusions, and the project's existing insufficient-history behavior SHALL remain effective. Setting a threshold SHALL NOT silently enable an automatic action, select human-review scoring, or reconfigure independent organization/global assessments. Existing active projects SHALL retain their frozen contracts.

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
- **WHEN** an otherwise valid draft activates without overriding the initial worker minima or history window
- **THEN** its frozen settings retain the twenty/twenty/thirty worker minima and a count limit of one hundred per signal, with human review unselected and its minimum inactive unless explicitly selected

#### Scenario: Time mode resolves its initial duration
- **WHEN** an otherwise valid draft selects time-based history and neither applicable organization defaults nor draft overrides supply a duration
- **THEN** activation freezes time mode with a ninety-day duration, leaving the initial count mode unchanged for projects that did not select time mode and leaving independent broader assessments unchanged

#### Scenario: An organization selects a different history window
- **WHEN** authorized organization defaults or a draft-project override select a time-based window with an explicit thirty-day duration and valid evidence minima
- **THEN** activation freezes those configured values instead of the initial count-window default, without changing the application-owned weights or independent broader assessments

#### Scenario: A configured organization duration takes precedence over the starting duration
- **WHEN** applicable organization defaults select a thirty-day time window and an otherwise valid draft supplies no duration override
- **THEN** activation freezes the inherited thirty-day duration rather than replacing it with the ninety-day starting duration

#### Scenario: Initial peer parameters scale with the source target
- **WHEN** a draft project with submission target ten activates under the initial peer defaults
- **THEN** its frozen configuration retains a floor of two, eighty-percent coverage, and eighty-percent consensus, requiring eight eligible other answers before testing agreement among all eligible peers

#### Scenario: A coverage override leaves consensus independent
- **WHEN** an authorized draft override changes peer coverage while keeping the initial consensus and worker comparison minimum
- **THEN** activation retains that coverage override alongside eighty-percent consensus and the thirty-comparison worker minimum without changing either automatically

### Requirement: Activation identifies impossible project-local evidence settings
For reputation rules using only this project's evidence, activation SHALL reject a known-answer enforcement minimum greater than the number of enabled scoreable task/question checks that one worker could answer through ordinary allocation. This theoretical maximum SHALL NOT be presented as a promise of per-worker delivery. Validation SHALL report the available count and required minimum to authorized managers. When known-answer scoring or enforcement is enabled, activation SHALL also return an advisory that shared task capacity can leave individual workers with fewer observations, including none. Activation SHALL validate an organization/global entry requirement's declared scope rather than reject it for lacking local checks; each worker's eligible broader history SHALL be evaluated at admission. This validation SHALL NOT alter submission targets, create qualification attempts, or reserve additional check capacity.

For automatic access rules, including contributors required by a combined admission score, activation SHALL also reject an evidence minimum greater than the applicable count-window limit. A project-local automatic peer rule SHALL be rejected when its computed other-worker minimum `max(peer_floor, ceil(peer_coverage_fraction * (submission_target - 1)))` exceeds `submission_target - 1`. This SHALL include targets one/two under the initial two-peer floor. Limits SHALL be evaluated for the rule's declared evidence scope; organization/global entry requirements SHALL NOT be rejected merely because the target project's local checks or submission target cannot supply that broader evidence. If an impossible minimum affects only reviewer information, activation SHALL return an advisory rather than reject the project. Both errors and advisories SHALL identify the computed required minimum and applicable upper bound; peer issues SHALL include the target, floor, and coverage used. Meeting an upper bound SHALL pass that feasibility check without guaranteeing actual delivery, evaluable answers, or consensus. Validation SHALL NOT change configured windows, minima, or submission targets automatically.

#### Scenario: A project cannot supply its own configured minimum
- **WHEN** project-local known-answer enforcement requires ten evaluated questions but the authored project contains only four enabled scoreable checks
- **THEN** activation fails with the four-versus-ten explanation and leaves the project draft

#### Scenario: A feasible total does not guarantee every worker is tested
- **WHEN** the project has enough authored checks in theory and activates
- **THEN** managers receive the ordinary-allocation advisory and individual assessments still report actual evidence counts

#### Scenario: A count window cannot satisfy an automatic rule's minimum
- **WHEN** an automatic rule requires thirty observations but its applicable history window includes at most twenty
- **THEN** activation fails with the thirty-versus-twenty explanation, leaving the project draft and its settings unchanged

#### Scenario: A peer rule requires more other workers than the task can supply
- **WHEN** a project-local automatic peer rule requires three other workers but the submission target is three
- **THEN** activation fails because each worker can have at most two other workers to compare against, without increasing the submission target

#### Scenario: A small target cannot meet the default peer floor
- **WHEN** a draft with submission target two uses the initial two-peer floor for a project-local automatic peer rule
- **THEN** activation rejects that rule because only one other worker is possible; if agreement is reviewer-only instead, activation returns the scoped advisory without manufacturing peer evidence or increasing the target

#### Scenario: Only reviewer information has an impossible minimum
- **WHEN** a reviewer-only signal requires thirty observations from a window capped at twenty and no automatic access rule depends on it
- **THEN** activation returns an advisory explaining the limit without failing solely for that minimum or fabricating an established score

#### Scenario: Configured minima equal the applicable upper bounds
- **WHEN** an automatic rule's minimum equals its count-window limit and a local peer minimum equals the submission target minus one
- **THEN** those bound checks pass, while actual evidence and consensus still determine whether the rules become usable

#### Scenario: Prior peer evidence comes from other projects
- **WHEN** a project's entry rule uses eligible global peer evidence but its own submission target is one
- **THEN** activation validates the global evidence limits rather than rejecting the entry rule for having no local peers

### Requirement: Reputation admission provides a path to initial project evidence
Admission rules SHALL declare their evidence scope and minimum. A project-local rule SHALL permit otherwise-eligible workers to participate while its local evidence is insufficient; its threshold SHALL apply once its minimum is met. Activation SHALL reject a project-only established-history requirement that denies insufficient local history. Projects requiring established reputation before the first task SHALL use eligible organization/global evidence that can be earned outside the target project. Genuinely missing broader evidence MAY deny admission when that requirement is explicitly configured. Each new work request SHALL evaluate the latest completed inputs in the required scopes; an earlier denial SHALL remain historical and SHALL NOT require separate project recalculation or manual clearance after broader reputation improves. An unprocessed initial assessment SHALL NOT be treated as missing evidence or require a queued-job wait; the ordinary admission request SHALL prepare it outside allocation locks when no completed assessment exists, then revalidate under those locks before issuance. Participation with insufficient local evidence SHALL NOT bypass account/audience restrictions, another rule whose failure conditions are met, or a separately configured organization/global entry requirement. This SHALL use the existing assessment and allocation lifecycle without introducing qualification attempts or guaranteeing known-answer delivery.

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
