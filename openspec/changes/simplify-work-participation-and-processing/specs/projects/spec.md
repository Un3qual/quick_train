## ADDED Requirements

### Requirement: Authoring guidance explains independently completable work units
Organization authoring guidance SHALL describe a Project as a collection of Tasks, each Task as one independently completable worker work unit with its own immutable inputs and the Project's pinned form, and Questions as the fields answered together within that Task. It SHALL explain that workers need not complete all Tasks, while submission requires every offered question to have a valid answer or allowed skip. Independent inputs SHOULD be divided into small Tasks instead of placing thousands of independent questions in one giant form. Guidance SHALL NOT imply heterogeneous per-Task forms or independent per-question allocation.

The frozen target SHALL mean valid submitted participations per Task, including allowed skips; it SHALL NOT promise that many non-skipped answers for every question. Rejection SHALL NOT generate replacement demand. Guidance SHALL distinguish this submission quota from a future actual-answer quota and describe the effect of enabling skips. Future payment offers SHALL use the completed worker work unit, subject to their explicit acceptance/payment contract, rather than require every worker to complete the Project; Finance implementation remains out of scope.

#### Scenario: An organization requests three responses per image
- **WHEN** an organization prepares one thousand images with a small repeated set of questions and a target of three
- **THEN** guidance describes one thousand image Tasks and three thousand worker participations, distributed across workers who may complete different numbers of Tasks

#### Scenario: A form permits skips
- **WHEN** the organization enables skips for its repeated form
- **THEN** guidance makes clear that three submitted participations may contain fewer than three answered outcomes for an individual question
