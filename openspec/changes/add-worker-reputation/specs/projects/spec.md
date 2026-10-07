## MODIFIED Requirements

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze authored tasks and inputs, bindings, slot counts/order policy, audience/external-access mode, review mode, submission target, project-wide skip rules, lease duration, and effective reputation configuration. Dataset/schema/form identities SHALL be immutable from creation, including in draft. Each task SHALL require the project's positive `submission_target` (default 1, maximum 2,147,483,647). `skip_allowed` and `reason_required` SHALL default to false and apply to the whole form. Review SHALL be automatic or manual; leases SHALL be 1–120 minutes with a 30-minute default. Tasks and TaskInputs SHALL exist as draft configuration before activation. Activation SHALL create no attempts, coverage rows, or progress projections. Child edits and activation SHALL serialize under the Project lock. After activation only title, lifecycle, and per-user allow/block overrides SHALL be editable as ordinary project configuration. Scoped known-answer corrections/disabling and reputation reinstatement SHALL remain available through their dedicated authorized operations without reopening the frozen collection configuration.

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

## ADDED Requirements

### Requirement: Organization defaults resolve into explicit project reputation settings
Reputation configuration SHALL support organization defaults and draft-project overrides using a bounded set of typed settings: enabled signals, minimum worker and peer samples, agreement thresholds and numeric tolerance, recent-history window, admission thresholds and evidence scope, and each signal's enforcement action. Score weights SHALL come from the central application definition, not organization/project overrides, and activation SHALL retain their effective values with the frozen configuration. Configuration management SHALL use explicit organization scope, active account/organization/membership, and the required management capability; foreign references SHALL fail closed. Project settings SHALL resolve atomically at activation into one complete effective configuration. Later organization-default or application-default weight changes SHALL NOT silently change an active project's scoring or enforcement rules. Customer-authored formulas and weight overrides SHALL NOT be accepted. A combined-score admission requirement SHALL select at least one enabled contributing scoring signal; disabled signals SHALL NOT count as missing evidence. Invalid combinations or unsupported grading contracts SHALL fail activation without partially freezing the project.

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

#### Scenario: Admission requires a combined score with no contributing signals
- **WHEN** draft configuration requires a combined reputation score but selects no enabled contributing scoring signals
- **THEN** activation rejects the unusable requirement rather than producing permanent provisional admission or a fabricated passing score

### Requirement: Activation identifies impossible project-local evidence settings
For reputation rules using only this project's evidence, activation SHALL reject a known-answer enforcement minimum greater than the number of enabled scoreable task/question checks that one worker could answer through ordinary allocation. This theoretical maximum SHALL NOT be presented as a promise of per-worker delivery. Validation SHALL report the available count and required minimum to authorized managers. When known-answer scoring or enforcement is enabled, activation SHALL also return an advisory that shared task capacity can leave individual workers with fewer observations, including none. Activation SHALL validate an organization/global entry requirement's declared scope rather than reject it for lacking local checks; each worker's eligible broader history SHALL be evaluated at admission. This validation SHALL NOT alter submission targets, create qualification attempts, or reserve additional check capacity.

#### Scenario: A project cannot supply its own configured minimum
- **WHEN** project-local known-answer enforcement requires ten evaluated questions but the authored project contains only four enabled scoreable checks
- **THEN** activation fails with the four-versus-ten explanation and leaves the project draft

#### Scenario: A feasible total does not guarantee every worker is tested
- **WHEN** the project has enough authored checks in theory and activates
- **THEN** managers receive the ordinary-allocation advisory and individual assessments still report actual evidence counts

### Requirement: Reputation admission provides a path to initial project evidence
Admission rules SHALL declare their evidence scope and minimum. A project-local rule SHALL permit otherwise-eligible workers to participate provisionally while its local evidence is insufficient; its threshold SHALL apply once its minimum is met. Activation SHALL reject a project-only established-history requirement that denies insufficient local history. Projects requiring established reputation before the first task SHALL use eligible organization/global evidence that can be earned outside the target project. Missing broader evidence MAY deny admission when that requirement is explicitly configured. Provisional local participation SHALL NOT bypass account/audience restrictions, another rule whose failure conditions are met, or a separately configured organization/global entry requirement. This SHALL use the existing assessment and allocation lifecycle without introducing qualification attempts or guaranteeing known-answer delivery.

#### Scenario: A new worker starts a project-local assessment
- **WHEN** an otherwise eligible worker has insufficient local evidence and satisfies any configured organization/global entry requirement
- **THEN** the local rule permits provisional participation without fabricating a passing score, and begins applying its threshold once enough evidence exists

#### Scenario: A project requires its own history before collecting any
- **WHEN** draft configuration denies entry to workers lacking established history from that same project
- **THEN** activation fails with a scoped explanation that the rule must allow provisional local participation or use organization/global entry evidence

#### Scenario: An experienced worker qualifies from other projects
- **WHEN** a worker with no target-project history satisfies its established organization/global reputation requirement using eligible prior work
- **THEN** that requirement permits entry without demanding prior work in the target project

#### Scenario: A worker lacks required broader history
- **WHEN** a project explicitly requires established organization/global reputation and the worker has insufficient evidence in that scope
- **THEN** admission denies entry despite provisional local status, leaving projects that admit newcomers as the route to earning broader history

### Requirement: Introducing reputation preserves existing active projects
Deploying reputation SHALL NOT silently enable new admission thresholds or automatic restrictions on projects already activated under the previous contract. Their frozen collection configuration and issued evidence SHALL be preserved. New reputation enforcement SHALL be selected through the activation contract rather than a migration that opts existing active projects into changed rules.

#### Scenario: Reputation is deployed while workers are active
- **WHEN** an existing active project has live attempts and submitted evidence
- **THEN** deployment preserves its existing admission behavior, attempt access, review history, and collection target
