# Future product features

This is a backlog of desired features outside currently scoped implementation changes. It remains within OpenSpec, the repository's planning home. Approval of a direction is not approval of an unspecified implementation; promote an item into a dedicated change before building it.

## Multiple acceptable known answers

Status: desired future feature, recorded 2026-10-06. Ownership: question/answer-key authoring and grading, outside `add-worker-reputation`.

Allow an author to mark more than one answer as acceptable. For a single-choice sentiment question, both “slightly positive” and “positive” could be valid. This means either answer passes; it is different from requiring the worker to select both options in a multiple-choice answer.

The future design should define typed acceptable-answer sets, validation, matching, and correction/version semantics. Reputation should consume the grading outcome when this capability exists, without owning an alternative answer representation or changing score weights merely to support it.

## Question-level scoring controls

Status: approved future direction, recorded 2026-10-06. Requires question-contract design before implementation; outside the current reputation change.

Let authors control which questions contribute to quality scoring, especially peer agreement. A form containing both factual classification and personal preference should be able to evaluate agreement on the factual question while excluding the preference question. Decide the exact controls and their relationship to organization/project defaults in the future change; do not add a general formula system.

That change must address published question immutability and activation-time resolution. It will also require coordinated changes to reputation: select eligible questions before computing signal counts and scores, apply minimum-evidence rules to the selected observations, exclude disabled questions from enforcement, explain exclusions, and rebuild affected assessments under the correct pinned question contract. Existing active projects must retain their frozen behavior. The [reputation design](changes/add-worker-reputation/design.md#future-question-capabilities) records this dependency.

## Worker explanations and disputes

Status: approved future direction, explicitly deferred on 2026-10-06; outside `add-worker-reputation`.

Give workers understandable explanations of their reputation and restrictions, and a way to ask an authorized organization reviewer to reconsider potentially incorrect evidence or an unfair outcome. For example, a worker could report ambiguous instructions or an incorrect expected answer. Keep hidden answer keys, peer answers, and private organization evidence protected.

The future change must define what workers can see, how they submit a dispute, how reviewers respond, and how the resolution connects to existing key correction, recalculation, and reinstatement. Detailed workflow and response-time rules remain undecided. The current reputation change retains organization-side explanations and recovery actions; it does not include worker-facing explanation or dispute workflows.

## Qualification tests and requalification

Discussion placeholder only: [add-qualification-tests](changes/add-qualification-tests/proposal.md). Its authoring, grading, retry, eligibility, and reputation integration details remain for a future discussion.
