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

## Spatial grading for bounding boxes and segmentation

Status: approved future direction, recorded 2026-10-07. Ownership: question types, reference-answer authoring, and annotation comparison; outside the current reputation change.

Partial credit was approved on 2026-10-08. Award credit for correctly annotated parts of an answer rather than failing the entire question because one object or region is wrong. Missing/extra objects, incorrect labels, and inadequate spatial overlap must still reduce the result. Retain a breakdown so authorized reviewers can distinguish the correctly annotated parts from the errors. The exact scoring formula, overlap thresholds, and rules for object annotations versus class-level segmentation remain to be discussed.

Allow organizations to supply trusted reference boxes or segmentation masks and automatically compare worker annotations with reasonable tolerance. Evaluate object labels, overlapping regions, and missing/extra objects; identical coordinates or pixels should not be required. Intersection over Union (IoU) is a candidate overlap measure, not a complete quality rule or a universal acceptance threshold. Producing a reference once can support grading many workers' answers to the same inputs; it does not guarantee that ordinary allocation delivers those questions to every worker.

The spatial change must extend reputation's grading-input, quality-aggregation, and reporting contracts to preserve fractional credit instead of rounding it to a full pass or failure. Keep the worker's actual evaluated-question count separate from earned credit and annotation counts; multiple objects in one question must not manufacture additional worker evidence. Specify how partial grades affect known-answer and peer metrics, scoped pooling, explanations, corrections, and any configured access threshold. The current reputation change retains its approved binary matching for supported non-spatial families; this direction does not change selection/ranking matching, quality weights, or evidence minima.

Specify annotation representations, published-contract validation, object matching, acceptable overlap, and correction/version behavior alongside the relevant question/media capability. The same type-specific comparison can support peer agreement, which remains weaker evidence than matching a trusted reference. Coordinate reputation eligibility, observation counts, provenance, and recalculation when this capability is implemented; keep geometry outside the reputation calculation and do not create a generic grader framework in advance. Free-text semantic grading remains a separate undecided capability. See the [reputation integration boundary](changes/add-worker-reputation/design.md#future-question-capabilities) and [HumanSignal's spatial-comparison metrics](https://docs.humansignal.com/guide/agreement_metrics).

## Review sampling and budgets

Status: approved future direction, recorded 2026-10-07. Ownership: answer-review workflow; outside `add-worker-reputation`.

Let organizations choose a project review budget or sample size without committing to a review quota per worker. Include a random sample for investigating overall output quality and instruction problems, with additional targeted investigation when needed. Record how responses were selected, distinguishing routine/random sampling from suspicion-driven review. An illustrative budget such as one hundred reviews across three hundred workers is not a guarantee of statistical confidence or evidence for every individual worker.

Specify selection, authorization, budget limits, and how sampling interacts with frozen automatic/manual review modes, effective verdicts, result visibility, and corrections. Do not automatically treat unsampled answers as human-approved, or imply that a targeted review queue estimates the acceptance rate of all submissions. Reviews must remain attributable to actual submitted answers and workers; a project-wide sample rate cannot establish an unreviewed worker's quality or satisfy their minimum evidence.

The [reputation contract](changes/add-worker-reputation/specs/worker-reputation/spec.md#requirement-human-review-is-supplementary-worker-evidence) specifies consumption of actual substantive reviews, supplementary human-review scoring unselected by default, and explicit opt-in and insufficient-evidence rules. This future capability supplies sampling workflow and provenance rather than a second reputation scorer. [Labelbox's quality strategy](https://labelbox.com/guides/how-to-create-a-quality-strategy-for-your-data-labeling-project/) provides a precedent for reducing manual review to a sample while using benchmarks and applicable consensus.

## Worker explanations and disputes

Status: approved future direction, explicitly deferred on 2026-10-06; outside `add-worker-reputation`.

Give workers understandable explanations of their reputation and restrictions, and a way to ask an authorized organization reviewer to reconsider potentially incorrect evidence or an unfair outcome. For example, a worker could report ambiguous instructions or an incorrect expected answer. Keep hidden answer keys, peer answers, and private organization evidence protected.

The future change must define what workers can see, how they submit a dispute, how reviewers respond, and how the resolution connects to existing key correction, recalculation, and reinstatement. Detailed workflow and response-time rules remain undecided. The current reputation change retains organization-side explanations and recovery actions; it does not include worker-facing explanation or dispute workflows.

## Qualification tests and requalification

Discussion placeholder only: [add-qualification-tests](changes/add-qualification-tests/proposal.md). Its authoring, grading, retry, eligibility, and reputation integration details remain for a future discussion.

## Organization and project score weights

Status: deferred on 2026-10-07; outside the current reputation change.

Allow organizations to choose signal weights, with project overrides if needed. The initial reputation implementation keeps weights centrally defined in application code and supplies them explicitly to the shared calculation, making developer adjustments straightforward without exposing customer controls. Other approved organization/project settings remain in scope.

Before exposing weights, specify valid combinations, treatment of missing evidence, activation-time freezing, and how local weighting remains independent of platform-controlled global reputation. Reuse the existing calculation and effective-configuration model rather than introducing customer-authored formulas or another scoring engine.
