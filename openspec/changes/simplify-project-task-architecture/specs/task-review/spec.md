## MODIFIED Requirements

### Requirement: Automatic and manual per-question review
Ash create validations SHALL enforce decision provenance for ordinary and bulk writes. Human-origin decisions SHALL require a requesting actor and request key; system-origin decisions SHALL have neither and SHALL only accept. These rules SHALL live in Elixir rather than a PostgreSQL business-rule check.

For a project frozen in `automatic` review mode, successful submission SHALL atomically append a system-origin acceptance for each answered outcome. For a project frozen in `manual` review mode, submission SHALL append no review decision and SHALL leave answered outcomes pending until an active account with active membership in the active owning organization and `tasks.review` appends an accept/reject decision under explicit organization/project scope. Submitted skips SHALL be non-reviewable: accept, reject, and correction actions SHALL reject them without appending a decision. A whole-response batch containing a skip SHALL fail atomically without appending any decisions. Every manual decision, correction, and whole-response review SHALL recheck the active account, active owning organization, active membership, and `tasks.review` under explicit organization/project scope. Reviewers SHALL not edit worker answers or manually review their own responses. Rejections SHALL require a nonblank reason. Whole-response review SHALL persist per-question decisions with atomic all-or-nothing validation and no additional batch-size ceiling. Review and correction reasons SHALL have no task-specific byte ceiling; nonblank-reason requirements and existing request handling SHALL remain in force.

#### Scenario: An answered outcome is submitted in manual mode
- **WHEN** a worker successfully submits an answered outcome to a manual-review project
- **THEN** it remains pending with no system acceptance while the submission already counts toward its task target

#### Scenario: A response receives mixed decisions
- **WHEN** a reviewer accepts one submitted answer and rejects another
- **THEN** each question has its own attributable decision and the worker's immutable response stays unchanged

#### Scenario: A reviewer attempts self-review
- **WHEN** a user with review permission targets their own submitted response
- **THEN** the manual decision is denied

#### Scenario: A review request targets a submitted skip
- **WHEN** an authorized reviewer targets a submitted skip with an individual decision, correction, or whole-response batch that also selects an answered outcome
- **THEN** the request fails without appending any decision, the submitted evidence remains unchanged, and the attempt still counts once toward its task target

#### Scenario: The owning organization is inactive
- **WHEN** an active reviewer with active membership requests a decision, correction, or whole-response review for an inactive organization
- **THEN** the request is denied without appending decisions or changing evidence

### Requirement: Corrections are append-only and conflict-aware
Each QuestionResponse's review history SHALL be immutable and ordered. A decision SHALL identify its actor/system origin, verdict, creation time, and predecessor. The latest decision SHALL determine the effective verdict. A correction SHALL require a nonblank reason and expected current decision identity; a stale expectation SHALL conflict without changing history. Each manual decision or correction SHALL require a caller-supplied UUID request key, validated before persistence; any invalid UUID in a whole-response batch SHALL reject the entire batch without appending decisions. A decision request key scoped to QuestionResponse and requesting actor SHALL converge identical retries and reject different content under the same key for that outcome. Another QuestionResponse SHALL have an independent key scope even when it answers the same form question. Corrections SHALL remain permitted in completed/archived projects but SHALL not reopen collection there. All effectively accepted evidence SHALL remain visible.

#### Scenario: One reviewer reuses a key across responses
- **WHEN** a reviewer uses the same request key for two different QuestionResponses answering the same form question
- **THEN** each authorized decision is recorded independently, an identical retry for either outcome returns its own decision, and different content under that outcome's existing key conflicts

#### Scenario: Two reviewers race
- **WHEN** two decisions name the same current predecessor
- **THEN** one succeeds and the other conflicts; history never acquires two competing effective successors

#### Scenario: Acceptance is corrected after closure
- **WHEN** an authorized reviewer rejects an earlier accepted answer in a completed project with a valid predecessor and reason
- **THEN** a successor decision changes current results while the previous decision/submission remain intact and no new work is issued

## ADDED Requirements

### Requirement: Review is independent of collection completion
Task state SHALL derive from native submitted-attempt counts and frozen project configuration: satisfied when the submission target is met, otherwise cancelled if the project is completed/archived, otherwise open. Review status SHALL derive from each outcome's current effective decision, with skips distinct from pending answers. Corrections SHALL change accepted results without changing task satisfaction, live capacity, or terminal attempt states. No failure thresholds, attention state, counter reconciliation, or follow-up assignment SHALL be maintained.

#### Scenario: A closed task receives a correction
- **WHEN** an accepted outcome in a satisfied completed project is rejected
- **THEN** the outcome's accepted-result visibility changes, while the task remains satisfied and all attempts stay terminal

## REMOVED Requirements

### Requirement: Progress is rebuildable from authoritative evidence
**Reason**: Replaced by explicit groups and whole-form submission targets.
**Migration**: Unreleased feature; regenerate the schema on a clean database.

### Requirement: Repeated failures stop automatic circulation
**Reason**: Replaced by explicit groups and whole-form submission targets.
**Migration**: Unreleased feature; regenerate the schema on a clean database.

### Requirement: Follow-up work creates linked new evidence
**Reason**: Replaced by explicit groups and whole-form submission targets.
**Migration**: Unreleased feature; regenerate the schema on a clean database.
