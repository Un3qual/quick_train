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
Reputation configuration SHALL support organization defaults and draft-project overrides using a bounded set of typed settings: enabled signals, minimum worker and peer samples, agreement thresholds and numeric tolerance, recent-history window, admission thresholds and evidence scope, and each signal's enforcement action. Score weights SHALL come from the central application definition, not organization/project overrides, and activation SHALL retain their effective values with the frozen configuration. Configuration management SHALL use explicit organization scope, active account/organization/membership, and the required management capability; foreign references SHALL fail closed. Project settings SHALL resolve atomically at activation into one complete effective configuration. Later organization-default or application-default weight changes SHALL NOT silently change an active project's scoring or enforcement rules. Customer-authored formulas and weight overrides SHALL NOT be accepted. A combined answer-quality admission requirement SHALL select at least one enabled known-answer correctness, substantive human-review, or peer-agreement signal configured for automatic access decisions. Reliability and experience SHALL remain separate inputs for their own permitted rules and SHALL NOT be accepted as combined-score contributors. Disabled and reviewer-only signals SHALL NOT contribute to its value or count as missing evidence. Organization/global entry requirements SHALL obey the same signal selection without changing those independent assessments. Invalid combinations or unsupported grading contracts, including gates using aggregates with excluded contributors, SHALL fail activation without partially freezing the project.

#### Scenario: A project overrides organization defaults
- **WHEN** a draft project overrides the disagreement action and then activates
- **THEN** activation freezes that explicit action together with the resolved remaining defaults

#### Scenario: Organization defaults change later
- **WHEN** an authorized manager edits defaults after a project activates
- **THEN** the active project's effective settings remain unchanged while later activations can use the revised defaults

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

### Requirement: Activation identifies impossible project-local evidence settings
For reputation rules using only this project's evidence, activation SHALL reject a known-answer enforcement minimum greater than the number of enabled scoreable task/question checks that one worker could answer through ordinary allocation. This theoretical maximum SHALL NOT be presented as a promise of per-worker delivery. Validation SHALL report the available count and required minimum to authorized managers. When known-answer scoring or enforcement is enabled, activation SHALL also return an advisory that shared task capacity can leave individual workers with fewer observations, including none. Activation SHALL validate an organization/global entry requirement's declared scope rather than reject it for lacking local checks; each worker's eligible broader history SHALL be evaluated at admission. This validation SHALL NOT alter submission targets, create qualification attempts, or reserve additional check capacity.

For automatic access rules, including contributors required by a combined admission score, activation SHALL also reject an evidence minimum greater than the applicable count-window limit. A project-local automatic peer rule SHALL be rejected when its minimum number of other workers exceeds `submission_target - 1`. Limits SHALL be evaluated for the rule's declared evidence scope; organization/global entry requirements SHALL NOT be rejected merely because the target project's local checks or submission target cannot supply that broader evidence. If an impossible minimum affects only reviewer information, activation SHALL return an advisory rather than reject the project. Both errors and advisories SHALL identify the required minimum and applicable upper bound. Meeting an upper bound SHALL pass that feasibility check without guaranteeing actual delivery, evaluable answers, or consensus. Validation SHALL NOT change configured windows, minima, or submission targets automatically.

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
