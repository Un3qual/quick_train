## MODIFIED Requirements

### Requirement: Activation freezes collection configuration
Activation SHALL atomically validate and freeze the cohort, dataset/schema/form references, bindings, slot counts/order policy, selection mode, audience/external-access mode, review mode, per-question policies, coverage target, and lease duration. Activation SHALL initialize coverage rows for the frozen cohort without issuing tasks; activation retries SHALL not reset existing exposure counts. Each form question SHALL have a positive accepted-answer target, skip permission, reason-required setting, and positive failure threshold. Selection SHALL be `balanced` or `explicit`; review SHALL be `automatic` or `manual`; lease duration SHALL be 1–120 minutes with a 30-minute default. Child edits and activation SHALL serialize so an edit is either included in validation or rejected after freezing. Authorized activation retries SHALL return the existing active project. After activation only title, lifecycle, and explicit per-user allow/block overrides SHALL be editable.

#### Scenario: A draft edit races activation
- **WHEN** enrollment or policy editing competes with activation
- **THEN** either the complete edit commits first and is validated, or activation commits first and the edit fails without modifying the frozen contract

#### Scenario: New imports do not enter active work
- **WHEN** another revision or dataset item is imported after activation
- **THEN** the active project's cohort and every issued input remain unchanged; enrollment requires a new project

#### Scenario: A manager changes worker access after activation
- **WHEN** an authorized manager adds, changes, or removes a per-user allow/block override on an active project
- **THEN** the edit takes the Project lock and rechecks current `projects.manage` authority without requiring draft state; frozen configuration edits still fail
