## MODIFIED Requirements

### Requirement: Coverage measures issued groups independently of answers
Activation SHALL initialize one zero-exposure coverage row per frozen cohort item in the same transaction, without issuing tasks. Allocation SHALL not initialize or rewrite the whole cohort on each request. Coverage SHALL count an item's appearances across distinct issued tasks, including tasks later cancelled, independently of per-question answer counts. Existing-task replication and follow-ups SHALL not increase item coverage. Balanced selection SHALL prioritize under-covered items and least-exposed compatible companions; coverage targets SHALL be lower goals rather than hard upper bounds because companions may exceed their own goals while another item remains under-covered. Once every item's coverage goal is met, balanced mode SHALL create no further groups but SHALL continue eligible existing-task work. Answer targets SHALL belong to an exact task/question; answers to a new group SHALL not fulfill another group's demand. Explicit mode SHALL lock and issue the next authored group by position with atomic consumption and lock only that group's coverage rows. It SHALL not lock the whole cohort or skip a locked earlier group; such contention SHALL return `retry_later`. Balanced mode SHALL retain its cohort-wide least-exposure selection and stable lock order. Only `balanced` and `explicit` SHALL be accepted.

#### Scenario: Replication does not invent coverage
- **WHEN** three workers answer the same issued pair
- **THEN** each underlying item has one group exposure while question progress contains three attributable answers

#### Scenario: A straggling item needs a companion
- **WHEN** an under-covered item can only form a valid group with an item already at its coverage target
- **THEN** balanced selection can issue the group and count the companion's additional exposure

#### Scenario: Covered items still need answers on existing tasks
- **WHEN** every item meets its coverage goal and a worker has attempted all remaining unsatisfied tasks
- **THEN** ordinary allocation returns `no_work_for_worker` without creating different groups or closing the project; other eligible workers or deliberate linked follow-ups can fill the existing task targets

#### Scenario: Unrelated explicit-group coverage is locked
- **WHEN** another transaction locks coverage used only by a later authored group
- **THEN** issuance of the next group can proceed without waiting for that unrelated row

#### Scenario: The next explicit group is locked
- **WHEN** the next unissued authored group is locked by another transaction
- **THEN** allocation returns `retry_later` without consuming a later group or changing coverage
