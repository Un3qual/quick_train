## Purpose

Give organizations private, explainable summaries of their known-answer check design and recurring answer mismatches, without changing worker scoring or collection behavior.

## ADDED Requirements

### Requirement: Quality reports require scoped management or review authority
Every report SHALL declare its owning organization and project and require an active authenticated account, active owning organization, active membership and the appropriate explicit capability. Check-design inventory and expected-answer distribution SHALL require `projects.manage`; submitted-answer quality summaries, error patterns and exact-question drilldown SHALL require `tasks.review`. An actor holding both grants SHALL be able to read both report classes. These operations SHALL grant no general Forms, dataset, source-answer or cross-organization browsing authority. Mere project-read permission, organization membership or authority to perform work SHALL NOT grant report access. Foreign and nonexistent targets SHALL fail without distinguishable disclosure. Protected reads SHALL authorize before capture and recheck current authority through a fresh read after the evidence transaction closes, outside its fixed snapshot, before returning results. Lost authority or a failed final check SHALL deny disclosure without changing the captured evidence.

Worker sessions SHALL retain their existing account-required, optional-membership audience routes. The reports SHALL expose no hidden keys or private answer evidence through those routes and SHALL add no worker interactions, worker explanation workflow or disputes. Management authority alone SHALL NOT grant submitted-answer diagnostics, and review authority alone SHALL NOT grant key/settings mutations.

#### Scenario: A manager inspects check design without answer-review authority
- **WHEN** an active member with `projects.manage` and no `tasks.review` requests their project's check inventory
- **THEN** they receive the scoped inventory and applicable expected-answer counts without submitted-answer error patterns or supporting worker answers

#### Scenario: A reviewer investigates answer patterns
- **WHEN** an active member with `tasks.review` requests their project's question-quality summary and drilldown
- **THEN** they receive permitted diagnostics and supporting own-organization evidence without key mutation authority

#### Scenario: A caller substitutes a foreign project
- **WHEN** a caller supplies a project outside the declared organization, a nonexistent target or a target after losing the required authority
- **THEN** no protected report or distinguishable target information is disclosed

#### Scenario: Authority is revoked during evidence capture
- **WHEN** a caller was authorized before capture but their account, organization, membership or required grant is revoked after its snapshot began and before the final authority check
- **THEN** the check outside that snapshot observes the revocation and denies the report without returning protected results

### Requirement: Check design is summarized independently of worker evidence
A check SHALL mean a successfully authored private known-answer key designated for an exact task/question/input contract. Check-design reports SHALL group current project task/question instances by their pinned published question identity, showing authored check counts, enabled supported check counts, disabled checks and questions with no designated checks. They SHALL distinguish having no checks from having checks that are currently disabled. Rejected unsupported-key requests SHALL NOT create an inventory entry or an unsupported-check category. A key revision SHALL NOT count as another authored check, and removed draft tasks SHALL NOT appear as current project inventory. A project SHALL be able to inspect draft inventory as well as its frozen active contract.

For boolean and static single-choice questions, reports SHALL count expected canonical values among enabled supported checks, including valid categories with zero checks. Different published question contracts SHALL NOT be merged. Task-input identities SHALL NOT be treated as comparable categories across different task inputs merely because their labels or positions match. Initial categorical distributions SHALL be unavailable for task-input choices and other answer families; their inventory and supported match-rate diagnostics SHALL remain available independently.

Reports SHALL explain that authored-check counts describe reference design rather than checks actually delivered to each worker, worker minimum evidence or statistical confidence. An uneven distribution or a question without checks SHALL be advisory only: it SHALL NOT enforce balance, invalidate keys, pause collection or restrict workers. Report inspection SHALL preserve the existing key-authoring and activation rules; active key repair SHALL use existing authorized correction/disabling/re-enabling, while changes to frozen design or instructions require the appropriate future contract.

#### Scenario: Boolean checks all expect the same answer
- **WHEN** a pinned boolean question has twenty-four enabled supported checks expecting true and none expecting false
- **THEN** the check-design report shows true twenty-four and false zero for investigation without rejecting the design or requiring a balance

#### Scenario: A question lacks currently usable checks
- **WHEN** one question has no designated keys and another has only disabled keys
- **THEN** the report distinguishes those conditions and does not imply either supplied worker correctness evidence

#### Scenario: Unsupported key authoring is rejected
- **WHEN** an author requests unsupported grading for a question without a designated key and authoring fails
- **THEN** the inventory continues to report that question as having no designated checks, without counting the rejected request as an authored or unsupported check

#### Scenario: Task-input display labels are reused
- **WHEN** different tasks use the same choice label or position for different input identities
- **THEN** the inventory counts their checks without inventing one cross-task expected-answer category

### Requirement: Project diagnostics expose question results and categorical answer patterns
Project question-quality summaries SHALL group evaluated submitted answers by pinned question identity, reporting evaluated, correct and incorrect counts and match rate when nonempty, with drilldown to exact task/question/input diagnostics. They SHALL use the shared known-answer eligibility and typed matching contract: enabled supported current keys, valid submitted answered outcomes, and no skips, absent or unfinished answers. Worker review verdicts SHALL NOT replace key matching, and workers' EWMA weights, minimum evidence and reinstatement cutoffs SHALL NOT change this all-history diagnostic sample. A zero denominator SHALL produce unavailable accuracy rather than a success or failure rate. Each evaluated answer SHALL contribute once to its question summary regardless of retries or review actions.

For comparable boolean and static single-choice questions, reports SHALL additionally show counts of reference-value/submitted-value pairs under canonical identity, including matching pairs and common mismatches. Other supported families SHALL retain match counts and exact diagnostics without implying that a categorical error breakdown exists. Reports SHALL show denominators alongside rates and errors; project summaries SHALL describe collected results against supplied references rather than establish each worker's quality or a single overall project-quality score.

These diagnostics SHALL NOT declare a worker or reference definitively wrong from a frequent mismatch, adopt peer majority as a trusted reference, or automatically change keys, project state, review decisions, worker reputation, access, pay, immutable submissions or exports. Existing key corrections SHALL remain attributable management actions with their existing assessment-repair effects.

#### Scenario: A high match rate hides a recurring confusion
- **WHEN** ninety-five of one hundred evaluated answers match and the five mismatches all submit category B against reference A
- **THEN** the question summary shows ninety-five correct, five incorrect and 95%, and its categorical breakdown identifies the five A-to-B pairs without an automatic worker penalty or key change

#### Scenario: Most workers disagree with a reference
- **WHEN** many submitted categorical answers differ from the supplied key
- **THEN** reviewers can investigate the reference, instructions or answers through the counts and exact diagnostics, without automatically declaring the majority correct or the key invalid

#### Scenario: A question has no evaluable answers
- **WHEN** its keys are disabled or no valid submitted answers can be evaluated
- **THEN** the summary reports no evaluated successes or failures and unavailable accuracy, independently of worker-assessment states

### Requirement: On-demand reports use coherent bounded read results
Each report SHALL capture its authorized project contract, relevant current key revisions/enabled states, necessary source facts and one server cutoff in a coherent read snapshot. Project summaries SHALL NOT combine independently captured exact-question responses as though they shared one snapshot. Returned question groups SHALL identify their pinned published question, evaluated/correct/incorrect counts, available match rate, cutoff and current-key all-history diagnostic basis. Key revisions and enabled states SHALL be captured internally with the answers they grade; changes committed before capture SHALL be reflected and changes after capture SHALL NOT alter the response.

Reports SHALL reuse reputation's bounded in-snapshot answer processing, including groups larger than one answer page. All source reads, matching and count reduction SHALL finish within that same snapshot without retaining the complete submitted answer population or using separate page transactions. Page size SHALL NOT change full-group totals. Compact canonical pair counters MAY grow with the applicable authored options; they SHALL NOT retain copies of individual submitted answers. Incomplete or failed processing SHALL return no partial counts as a complete report.

Project summaries SHALL NOT return a manifest of all contributing task/question/input/key revisions, paginate key-revision references or introduce a revision-set fingerprint. Authorized reviewers SHALL inspect an individual exact task/question/input through the existing diagnostic drilldown, which SHALL identify that request's captured key revision, enabled state, counts and cutoff. A later request SHALL use its own identified snapshot rather than promise to reproduce an earlier summary. Full historical report manifests/replay SHALL remain outside this change and subject to a concrete future auditing need.

Reported counts SHALL use ordinary numeric GraphQL Int in the initial API, with larger count representations deferred. Question groups and categorical pair lists SHALL be bounded and paginated, with counts covering the stated group rather than only its returned page. Reports SHALL have no persisted completed-report authority, background refresh or pending-report lifecycle. They SHALL remain independent of completed/pending worker assessments and SHALL reuse worker-reputation's exact-question diagnostic semantics rather than another grading rule or configurable report window.

#### Scenario: A key is corrected during calculation
- **WHEN** a project report captures key revision three and revision four commits afterward
- **THEN** its counts consistently use the internally captured revision three and identify their report cutoff, while the next report request reflects revision four without waiting for worker-assessment recalculation

#### Scenario: One question group uses several task-specific keys
- **WHEN** a project summary groups answers to one pinned question across tasks whose keys have different current revisions or enabled states
- **THEN** it grades each answer against its own captured applicable key, excludes disabled evaluations and returns the group's totals and cutoff without implying a shared key revision or returning a paginated revision manifest

#### Scenario: Drilldown follows an earlier summary
- **WHEN** a reviewer opens an exact-question diagnostic after a key correction committed following their project summary
- **THEN** drilldown identifies its newer cutoff and key revision rather than claim it reproduces the earlier summary snapshot

#### Scenario: A report spans several pages
- **WHEN** the authorized project has more question groups or categorical pairs than one page permits
- **THEN** the response returns a bounded page with counts for each stated full group, without truncating the underlying evaluated sample to that page
