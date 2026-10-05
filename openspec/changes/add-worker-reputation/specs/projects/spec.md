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
Reputation configuration SHALL support organization defaults and draft-project overrides using a bounded set of typed settings: enabled signals and weights, minimum worker and peer samples, agreement thresholds and numeric tolerance, recent-history window, admission thresholds and evidence scope, and each signal's enforcement action. Configuration management SHALL use explicit organization scope, active account/organization/membership, and the required management capability; foreign references SHALL fail closed. Project settings SHALL resolve atomically at activation into one complete effective configuration. Later organization-default changes SHALL NOT silently change an active project's scoring or enforcement rules. Customer-authored formulas SHALL NOT be accepted. Invalid combinations or unsupported grading contracts SHALL fail activation without partially freezing the project.

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
- **WHEN** activation encounters invalid weights, insufficient comparison settings, or an unsupported grading family
- **THEN** it returns scoped validation issues and leaves the project editable in draft

### Requirement: Introducing reputation preserves existing active projects
Deploying reputation SHALL NOT silently enable new admission thresholds or automatic restrictions on projects already activated under the previous contract. Their frozen collection configuration and issued evidence SHALL be preserved. New reputation enforcement SHALL be selected through the activation contract rather than a migration that opts existing active projects into changed rules.

#### Scenario: Reputation is deployed while workers are active
- **WHEN** an existing active project has live attempts and submitted evidence
- **THEN** deployment preserves its existing admission behavior, attempt access, review history, and collection target
