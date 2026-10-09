## Purpose

Give organizations explainable worker-quality evidence and recoverable control over future project work while preserving submitted answers, existing attempts, and organization privacy.

## ADDED Requirements

### Requirement: Scoped assessments preserve evidence and uncertainty
Reputation SHALL assess the existing global User at project, organization, and platform-controlled global scope. Assessments SHALL distinguish known-answer correctness, substantive human review, peer agreement, reliability, and experience, and expose contributing counts, the evidence window, and calculation provenance to authorized readers. Evidence state SHALL be exactly one of not applicable, insufficient evidence, or established. Disabled/unselected contributors SHALL be not applicable; enabled contributors below their minimum SHALL have insufficient evidence, including at zero observations; contributors meeting the minimum SHALL be established. Counts SHALL distinguish zero observations from a small sample without another evidence state. As-of cutoff and pending refresh SHALL be separate metadata; a pending update SHALL NOT by itself change the evidence state or deny access. Each reported signal sample SHALL identify its oldest and newest original source-event times, independently of the calculation cutoff; an empty sample SHALL have unavailable observation dates. Corrections and recalculation SHALL NOT make the supporting work appear newer. Admission SHALL evaluate the latest completed inputs from each required scope on each new work request. Global calculations SHALL use platform-defined eligible evidence and SHALL NOT average scores calculated under different local settings. One organization's settings SHALL NOT change another organization's assessment or the global calculation's weights, contributor selection, minima, comparison thresholds, or history window. Source eligibility SHALL follow the broader-assessment contract below, including the shared exclusion of disabled project peer comparisons.

#### Scenario: A new worker has insufficient history
- **WHEN** the worker has fewer observations than the configured minimum for an enabled signal
- **THEN** that signal has insufficient evidence and reports its actual count, without a fabricated success or failure score

#### Scenario: Organizations use different settings
- **WHEN** two organizations give the same worker different local assessments
- **THEN** each assessment retains its scope and provenance, and neither local score overwrites the other or becomes an unqualified global average

#### Scenario: Zero observations and a small sample use one state
- **WHEN** one enabled signal has no observations and another enabled signal has some observations below its configured minimum
- **THEN** both have insufficient evidence with their actual counts rather than separate states

#### Scenario: An established assessment awaits an update
- **WHEN** an established published assessment needs recalculation
- **THEN** its evidence state remains established as of its recorded cutoff, with pending refresh reported separately and that completed assessment still usable by a fresh admission evaluation

#### Scenario: A reported signal has no observations
- **WHEN** an authorized reader inspects a signal with an empty eligible sample
- **THEN** its contributing count is zero and its observation dates are unavailable, while calculation cutoff and evidence state retain their separate meanings

### Requirement: Broader assessments pool source evidence under scoped rules
Project assessments SHALL use the worker's eligible evidence from that project. Organization assessments SHALL pool the worker's eligible authoritative source evidence across projects owned by that organization and apply its current organization reputation settings with application-owned weights. Global assessments SHALL pool eligible authoritative source evidence across organizations and apply platform-controlled settings. Broader assessments SHALL NOT average project or organization percentages, reuse their combined scores, or exclude source observations merely because the narrower assessment has insufficient evidence. Organization-default changes SHALL refresh the organization assessment and affect later project activations without changing already-frozen project settings; draft or frozen project overrides SHALL NOT reconfigure the organization assessment.

Each broader scope SHALL apply source eligibility, deduplication, its own comparison rules, cutoff, and history selection before calculating rates and applying its own worker minima. A count window of N SHALL select at most N eligible observations per signal across the pooled scope, not N from every source project or organization. Rebuilding SHALL use source facts rather than locally windowed samples or verdicts derived from another scope's comparison settings. Original observation identities and times, known-answer precedence, correction handling, and reviewer-only admission exclusions SHALL remain effective.

Initial organization and global quality defaults SHALL select known-answer correctness and peer agreement, leaving human review supplementary and unselected. Their initial application-owned relative weights SHALL be sixty for correctness, thirty for human review when selected, and ten for peer agreement. Their initial worker minima SHALL be twenty evaluated known-answer answers, twenty substantive human-reviewed answers when selected, and thirty eligible worker peer comparisons; their initial history window SHALL select the most recent one hundred eligible observations independently per signal. These SHALL be explicit defaults for those scopes rather than inheritance from a particular project's settings. Authorized organization settings MAY adjust the supported selections, minima, comparison settings, and window for its assessment; global settings SHALL remain platform-controlled. Missing selected evidence SHALL retain the existing insufficient-evidence behavior rather than become failure or cause silent reweighting.

Eligible known-answer evidence SHALL be evaluable submitted answers to the exact applicable task/question/input contract under an enabled key and supported matching rule. Key correction or disabling SHALL repair affected scopes under the existing key contract. Eligible human-review evidence SHALL consist only of the worker's effective substantive human accept/reject decisions; local omission from scoring SHALL NOT erase those facts or prevent an independently selected broader contribution. Reliability SHALL use the existing eligible-attempt and return-classification rules in every scope. Project scoring selection SHALL NOT by itself invalidate known-answer, substantive review, or reliability source facts.

Peer evidence SHALL additionally require agreement scoring to be enabled in the source project's frozen configuration. Disabling project agreement scoring SHALL exclude that project's comparisons from scored peer evidence in project, organization, and global assessments, including worker minima and automatic access inputs. This SHALL be a shared source-eligibility boundary, not permission for a local setting to choose global weights, minima, consensus thresholds, or history windows. A reviewer-only agreement action SHALL NOT be confused with disabled agreement scoring: its eligible comparisons MAY contribute to broader reviewer summaries while every admission calculation retains its own reviewer-only exclusions. Enabled source projects SHALL still satisfy the assessed scope's completed-task, distinct-peer, consensus, and known-answer-precedence safeguards. Excluded source answers SHALL remain retained and available to appropriately authorized local reviewers as diagnostic evidence. No automatic subjective-question classifier or additional eligibility-setting hierarchy SHALL be introduced.

Global reputation SHALL describe general eligible work history, not certify competence for every task type. Project assessments SHALL remain specific to their own work, and explicitly configured broader entry requirements SHALL retain their existing behavior.

#### Scenario: Project percentages have different sample sizes
- **WHEN** the worker has ten correct known answers out of ten in Project A and thirty-six out of forty in Project B, both owned by one organization, and all fifty observations qualify for its selected window
- **THEN** organization correctness is forty-six out of fifty, or 92%, rather than the 95% unweighted average of project percentages

#### Scenario: Small project histories establish broader evidence
- **WHEN** two projects each supply fifteen eligible known-answer observations for the worker and the organization minimum is twenty
- **THEN** the organization applies its minimum to the thirty pooled observations, even though neither project individually meets that minimum

#### Scenario: A broader count limit applies after pooling
- **WHEN** several projects together supply more than one hundred eligible observations for one signal under the initial organization or global window
- **THEN** that assessment uses the most recent one hundred across its whole eligible scope, not one hundred from each project

#### Scenario: Local comparison settings differ from platform rules
- **WHEN** an agreement-enabled source project and the platform use different consensus requirements
- **THEN** global comparison uses the source answers under platform requirements rather than copying the project's scored comparison, while preserving the source contract and shared eligibility exclusions

#### Scenario: Subjective comparisons cannot reappear globally
- **WHEN** a preference project's frozen configuration disables agreement scoring and a worker gives a minority opinion
- **THEN** that project's comparisons contribute no scored peer successes, failures, minimum-evidence credit, or access effect in any scope; its answers remain available to authorized local reviewers

#### Scenario: An organization changes its own assessment settings
- **WHEN** an authorized organization changes its default worker minimum or history window
- **THEN** its organization assessment is refreshed and later activations can use the revised defaults, while active projects retain their frozen settings and the platform's global calculation settings remain unchanged

### Requirement: Answer quality reliability and experience have distinct roles
Assessments SHALL retain all five signals while distinguishing answer quality, completion reliability, and experience. A combined score in this change SHALL mean an answer-quality result whose possible contributors are known-answer correctness, substantive human review, and peer agreement only. Known-answer correctness SHALL measure matching against eligible supplied keys; substantive human review SHALL measure acceptance among answers with effective human accept/reject decisions, excluding automatic acceptance; peer agreement SHALL measure agreement among eligible completed comparisons under the existing safeguards. Known-answer correctness SHALL have the greatest weight when included, with peer agreement a smaller contribution. Signal selection, minimum evidence, known-answer precedence, and reviewer-only admission exclusions SHALL continue to apply, and combined quality SHALL use the normalized weighted-average contract below.

Reliability SHALL measure completion of work the worker deliberately takes on and SHALL remain separately inspectable and eligible for its own configured action. Reliability SHALL NOT contribute to the combined answer-quality score or its evidence minimum. Its evidence SHALL distinguish successful submissions, eligible expirations, excused and unexcused returns, returns awaiting review, organization/system cancellations, and direct assignments the worker never started. Reliability SHALL use the completion formula, original-outcome time contract, and return-classification rules below. Valid skips SHALL retain their existing meaning rather than automatically becoming poor answer quality.

Experience SHALL be reported as counts of answered questions from successfully submitted work under the experience contract below, with scope and history window identified, and SHALL carry no answer-quality weight. It SHALL NOT improve or lower the answer-quality score, substitute for the contributing quality signals' minimum samples, or make that combined result unavailable. Explicit broader-history entry requirements MAY use experience counts under the existing organization/global admission rules; project-local insufficient history SHALL continue to permit participation under that local rule. Authorized reports SHALL show quality, reliability, and experience separately without collapsing them into an overall weighted score.

#### Scenario: More experience does not award quality points
- **WHEN** two workers have equivalent established quality metrics, contributing signals, and effective weights but different submitted answered-question counts
- **THEN** their answer-quality scores are equal while their experience counts remain distinguishable

#### Scenario: Good answers accompany inconsistent completion
- **WHEN** a worker has established strong answer quality and a separately established poor completion-reliability metric
- **THEN** reviewers can inspect both results, reliability does not lower the answer-quality score, and any configured reliability action is evaluated independently

#### Scenario: Separate reliability and experience do not hide established answer quality
- **WHEN** contributing quality signals have sufficient evidence but reliability lacks evidence, or the worker has less experience than another worker
- **THEN** the combined answer-quality result remains available, while separately configured access requirements are still evaluated on their own inputs

#### Scenario: A broader-history rule uses experience
- **WHEN** a project explicitly requires a minimum number of eligible organization/global submitted answered questions
- **THEN** admission evaluates that requirement using scoped experience counts without adding quality points or treating the count as evidence that answers were correct

### Requirement: Experience counts submitted answered questions
Experience SHALL count valid answered QuestionResponses belonging to the assessed worker's successfully submitted attempts under the pinned task/question/input contract. Each authoritative submitted answered question SHALL contribute at most one experience observation per assessment scope, regardless of how many selections, objects, annotations, or other parts its answer contains. Submission or calculation retries SHALL NOT create duplicate experience. Skips, missing answers, saved drafts, unfinished/unsubmitted outcomes, and answers saved in returned, expired, or cancelled attempts SHALL NOT qualify. Successful submission SHALL suffice without waiting for the source task's full submission target to be reached.

Awaiting review, automatic acceptance, effective human acceptance, and effective human rejection SHALL follow the same experience eligibility. Review decisions/corrections, key correctness, peer agreement, and local quality-signal selection SHALL NOT change an otherwise eligible answered question's experience contribution. Experience SHALL describe submitted work performed rather than certification that its answers were correct. An allowed all-skipped submission SHALL count as one successful completion for reliability while supplying no experience observations.

Each scope SHALL apply its existing source filtering, deduplication, cutoff, and configured history window before reporting the experience count or evaluating a permitted broader-history requirement. Answered-question observations SHALL retain original submission time and stable source identity. Organization/global experience SHALL pool authoritative eligible answered questions under their own settings, without summing project counts that already applied local windows. The initial count window of one hundred SHALL therefore cap the selected experience count at one hundred answered questions, while all submitted source history remains retained. Authorized reports SHALL identify the count's question unit, scope, window, and supporting dates; a selected-window count SHALL NOT be presented as a lifetime total.

#### Scenario: A mixed submission adds question experience and one completion
- **WHEN** a worker successfully submits eight answered questions and two allowed skips, the selected history includes those answers, and the source task has not yet reached its full submission target
- **THEN** the submission contributes eight experience observations and one completed reliability attempt, without requiring further submissions or review

#### Scenario: Review corrections do not change experience
- **WHEN** eligible submitted answers include pending, automatically accepted, human-accepted, and human-rejected outcomes, and a human acceptance is later corrected to rejection
- **THEN** each answered question still contributes once to experience under the same selected history, while substantive human-review quality updates separately

#### Scenario: Many answer parts remain one question
- **WHEN** one eligible submitted question contains multiple selections or annotations and its submission is retried
- **THEN** the question contributes one experience observation, with no extra observations from its answer parts or retry

#### Scenario: All skips complete work without adding question experience
- **WHEN** a worker successfully submits a task with every question explicitly skipped under the frozen skip rules
- **THEN** the attempt supplies one completion for reliability and no experience observations, while its immutable skipped outcomes remain retained

#### Scenario: The experience count reflects its selected history
- **WHEN** a worker has one hundred twenty eligible submitted answered questions in a scope using the initial count window
- **THEN** experience reports the selected one hundred answered questions with that scope/window identified, retaining all one hundred twenty source answers without presenting one hundred as a lifetime total

### Requirement: Reliability includes unexcused returns and excludes legitimate returns
Within the declared scope and configured history window, established reliability SHALL equal C / (C + E + U), where C is successful completed attempts, E is eligible expirations of work voluntarily claimed or started, and U is eligible returned attempts classified as unexcused. Each attempt SHALL contribute at most once. Organization/system cancellations, live attempts awaiting an outcome, and direct assignments never started SHALL be excluded. Returns of unstarted direct assignments SHALL remain inspectable but SHALL NOT become scored failures merely through classification. Excused returns and returns awaiting review SHALL contribute neither completion credit nor failure to the calculation or its minimum-evidence count. Successful valid submissions containing allowed skips SHALL count as completions while answer-quality evidence follows its own rules. With enabled reliability and a zero denominator or fewer eligible outcomes than its configured minimum, the result SHALL have insufficient evidence and no usable enforcement score; disabled reliability SHALL remain not applicable. Reliability SHALL NOT change the combined answer-quality score.

Initial project, organization, and global reliability defaults SHALL require twenty eligible task attempts in the assessed scope's selected history before reliability is established. The minimum SHALL use the same C + E + U denominator as the score, counting each eligible attempt once after scope filtering, deduplication, cutoff, and configured history selection. Excluded outcomes SHALL NOT satisfy the minimum; their retained facts and authorized reporting SHALL remain available. Below the minimum, enabled reliability SHALL report insufficient evidence with actual counts rather than a usable percentage, without making an otherwise established answer-quality result unavailable. The reliability minimum SHALL be a positive integer adjustable through authorized organization settings and draft-project overrides under the existing validation and activation-freezing contract. Global settings SHALL remain platform-controlled and independent of project overrides. The existing default count window of one hundred eligible observations per signal SHALL also apply to reliability; twenty SHALL be an evidence minimum, not a replacement window or a new automatic restriction rule.

#### Scenario: Twenty eligible attempts establish reliability
- **WHEN** the selected history contains eighteen successful completions, one eligible expiration, and one eligible return confirmed as unexcused under the initial reliability minimum
- **THEN** reliability is established at ninety percent using eighteen completions divided by twenty eligible attempts

#### Scenario: Neutral outcomes do not establish reliability
- **WHEN** the selected history contains eighteen successful completions and two excused returns, with any additional returns awaiting review or organization/system cancellations
- **THEN** only eighteen attempts satisfy the initial minimum, reliability remains insufficient without a usable percentage, and authorized reports retain the actual completion and excluded-outcome counts

#### Scenario: Broader history meets the reliability minimum
- **WHEN** a worker has ten eligible completions in each of two projects owned by one organization, all within the applicable selected histories and using the initial reliability minima
- **THEN** each project has insufficient reliability evidence while the organization's pooled twenty attempts establish one-hundred-percent reliability; eligible global history applies its independent scoped rules

#### Scenario: A corrected return drops reliability below its minimum
- **WHEN** the selected history contains eighteen completions, one eligible expiration, and one unexcused return, and a reviewer corrects that return to excused without other eligible attempts available in the window
- **THEN** recalculation uses nineteen eligible attempts and reports insufficient reliability evidence under the initial minimum, retaining the corrected return, its prior classification, and the actual counts

#### Scenario: Excused returns do not lower reliability
- **WHEN** the selected evidence contains ninety completions, five eligible expirations, five unexcused returns, and ten excused returns
- **THEN** reliability is ninety percent when its minimum is met, using ninety completions divided by one hundred eligible outcomes and showing the ten excused returns separately

#### Scenario: A direct assignment was never started
- **WHEN** the worker returns or lets expire a direct assignment without starting it
- **THEN** that attempt contributes no reliability failure, while its actual outcome and any return classification remain inspectable

#### Scenario: A valid submission contains skips
- **WHEN** a worker successfully submits an attempt with allowed skipped outcomes
- **THEN** the attempt counts once as completed for reliability without making those skips successful answer-quality observations

### Requirement: Reliability history uses original outcome times
In project, organization, and global assessments, a successful completion's original event time SHALL be its successful submission time; an eligible expiration's original event time SHALL be the attempt's lease deadline; and a return's original event time SHALL be the worker's release time. These times SHALL govern count-window ordering, time-window membership, supporting observation dates, and applicable reinstatement cutoffs. Eligibility SHALL still require authoritative terminal outcomes captured in the evidence snapshot under the existing completion/expiration/return rules; a passed deadline alone SHALL NOT fabricate a terminal outcome.

Original times SHALL come from the owning attempt's retained facts: submitted/released attempts use their terminal transition time, while expired attempts use their immutable lease deadline rather than the time cleanup recorded expiry. Cleanup, scheduling, recalculation, human review, return classification/correction, and request retries SHALL NOT restart an outcome's age or create a duplicate attempt observation. Eligibility changes SHALL rerun ordinary history selection using the original event time and stable source-attempt identity. Native terminal-processing timestamps and retained classification history SHALL preserve their existing meanings rather than be overwritten to match reputation's selected event time.

#### Scenario: Delayed cleanup does not make an old expiration recent
- **WHEN** an eligible attempt's lease deadline was one hundred days ago and cleanup records its expired terminal outcome today
- **THEN** a ninety-day reliability window excludes that expiration using the original deadline, while the expired attempt and its actual cleanup/terminal time remain retained

#### Scenario: A late return classification preserves the release date
- **WHEN** a worker released an eligible attempt one hundred days ago and a reviewer classifies it as unexcused today
- **THEN** a ninety-day reliability window excludes that return using its release time, while authorized return reporting retains the reason, original return, and today's classification

#### Scenario: Count selection preserves the order of corrected returns
- **WHEN** an awaiting-review return becomes eligible through an unexcused classification after newer eligible completions or expirations were recorded
- **THEN** count-window selection places the return at its original release time using its stable attempt identity, without moving it ahead of newer outcomes or duplicating it

#### Scenario: A late release remains dated as an expiration
- **WHEN** a release operation obtains its locks after the attempt's deadline and records the ordinary expired outcome
- **THEN** an otherwise eligible reliability observation uses the lease deadline, not the attempted release or processing time, and supplies no additional returned-work observation

### Requirement: Return classifications preserve reasons and support repair
Worker returns SHALL capture the selected preset reason, custom Other text if present, and separate optional comment as source evidence under the [return-input contract](../task-allocation/spec.md#requirement-worker-returns-capture-reasons-without-waiting-for-classification). Each returned attempt SHALL have an effective classification of excused, unexcused, or awaiting review; without an authorized classification decision it SHALL be awaiting review. Return inspection, classification, and correction SHALL require explicit organization/project scope, an active account, active owning organization, active membership, and the existing `tasks.review` capability. Every operation, including request replay, SHALL recheck current authority and fail closed for foreign references. Reviewers SHALL NOT classify or correct their own returns. Decisions SHALL retain the actor, a nonblank reviewer explanation, creation time, predecessor, and source attempt/return provenance, separately from the immutable worker-provided fields. The worker's stated reason SHALL NOT by itself establish an excused return, and return frequency or time spent alone SHALL NOT establish an unexcused return. A preference for shorter/easier work on a task meeting its stated requirements SHALL be an unexcused reason; confirmed unusable inputs, conflicting instructions, or a task that cannot reasonably fit its lease SHALL be excused reasons.

All preset choices and custom text SHALL be worker claims rather than reviewer verdicts. This SHALL include both `time_limit` and `work_preference`: selecting either code alone SHALL NOT determine classification, contribute a reliability failure, or add a restriction. Authorized reviewers SHALL see the selected reason, custom Other text, and comment distinctly alongside classification/history and their own decision reasons. A reviewer SHALL still assess whether a claimed time-limit issue is an unrealistic lease or a preference for shorter ordinary work under the existing classification rules. Historical reasonless returns SHALL NOT acquire invented choices or text through migration or recalculation.

Authorized reviewers SHALL be able to inspect every returned attempt through bounded reads, including reasons, classifications, and history, and see the total return count with its excused, unexcused, and awaiting-review breakdown for the declared scope and report cutoff. Reliability summaries SHALL separately identify their scoring window, cutoff, eligible counts, and freshness. Awaiting-review returns SHALL stay visible without lowering reliability or independently adding a restriction. Classification and corrections SHALL trigger the existing affected-scope recalculation and publication path, retain previous decisions, and preserve the same logical observation and its original source-event time. Later classification SHALL NOT make old returns recent or eligible after a reinstatement cutoff. Classification SHALL NOT change task capacity, the attempt's terminal state, submitted answers, answer-review verdicts, or sealed exports. Repeated requests SHALL NOT duplicate decisions or contributions. No worker dispute or appeal lifecycle SHALL be introduced by this organization-side classification workflow.

Classification history SHALL be append-only, with the latest decision determining the effective classification. Initial classifications and corrections, including a decision returning a case to awaiting review, SHALL require a nonblank reviewer explanation. The worker-input text limits SHALL NOT become a limit on reviewer explanations; existing request handling SHALL remain in force. Only actual released attempts SHALL qualify for return decisions, including retained returns in completed/archived projects without reopening collection. Submission, expiry, and cancellation SHALL NOT be reclassified as returns.

Each classification/correction SHALL require an expected current decision identity, explicitly absent for the first decision, and a caller-supplied UUID request key validated before persistence. Reuse the existing answer-review request and predecessor-check pattern while keeping return decisions separate and scoped to their source attempt. Under current authority, identical retries scoped to the returned attempt and requesting actor SHALL return the original decision/result without appending another decision or duplicating a reliability observation. Different content under the same key for that attempt/actor SHALL conflict. Another returned attempt SHALL have an independent key scope. An identical replay SHALL be recognized before applying the current-predecessor check, so an already successful request can be retried after its original predecessor changed. Replaying an earlier decision SHALL NOT replace a later effective classification. A new request with a stale expected predecessor SHALL conflict without changing history; two reviewers acting on the same prior decision SHALL permit only the first valid save, with the other required to refresh before deciding. Authorization, self-review exclusion, source scope, predecessor validation, and persistence SHALL remain coherent under concurrent decisions; concrete storage/lock integration remains subject to the shared publication contract.

#### Scenario: A reviewer cannot classify their own return
- **WHEN** the actor has current `tasks.review` in the owning organization but is also the worker who returned the attempt
- **THEN** classification and correction are denied without appending history or changing reliability inputs

#### Scenario: First decisions compete against the same empty history
- **WHEN** two authorized reviewers classify the same returned attempt using distinct request keys and an expected absence of previous decisions
- **THEN** only the first valid save appends a decision, and the second conflicts and must refresh without overwriting that decision

#### Scenario: A correction appends an explained decision
- **WHEN** an authorized reviewer supplies the expected latest decision, a valid new request key, and a nonblank explanation to correct an unexcused return to excused
- **THEN** the new decision becomes effective while the earlier decision, worker-selected reason, Other text, comment, and original release time remain retained and affected reliability inputs refresh normally

#### Scenario: A successful request is replayed after a later correction
- **WHEN** an authorized actor identically retries a previously successful classification request after another valid decision has corrected it
- **THEN** replay returns the original request's result without another decision, while the later classification remains effective and the return still supplies at most one reliability observation

#### Scenario: Changed retry content or a stale predecessor conflicts
- **WHEN** an actor reuses a returned-attempt/requesting-actor key with different content, or a new request expects a decision that is no longer current
- **THEN** the operation conflicts without changing classification/history or queuing a duplicate contribution

#### Scenario: Missing authority or invalid decision inputs change nothing
- **WHEN** return inspection or decision replay uses foreign scope or revoked membership/capability, or a decision has a blank explanation, invalid UUID key, or a source attempt that was not released
- **THEN** it fails without revealing foreign return evidence or persisting a classification/change to reliability inputs

#### Scenario: A return awaits verification
- **WHEN** a worker returns a task claiming unclear instructions and no reviewer has classified it
- **THEN** the return is awaiting review, its reason and unresolved status remain visible, and it contributes no reliability failure or completion credit

#### Scenario: The worker prefers a shorter task
- **WHEN** a reviewer establishes that the task meets its stated requirements and the return was a preference for shorter work
- **THEN** the attributed unexcused classification requests recalculation, and the eligible original return contributes one reliability failure after publication

#### Scenario: The task cannot reasonably fit its lease
- **WHEN** a reviewer confirms that the returned task cannot reasonably be completed within its lease
- **THEN** it is classified excused and excluded from reliability failures while remaining visible in return reporting

#### Scenario: A reviewer corrects an unexcused classification
- **WHEN** a reviewer finds that an unexcused return actually involved unusable inputs and corrects it to excused
- **THEN** the prior decision remains explainable and recalculation removes that return's failure contribution and reevaluates dependent admission without changing source evidence or renewing its age

### Requirement: Application-owned weights are explicit calculation inputs
Answer-quality weights SHALL be defined centrally in application code for the three eligible quality contributors and supplied explicitly to the shared reputation calculation. Initial application-owned weights in all three scopes SHALL be sixty for known-answer correctness, thirty for substantive human review, and ten for peer agreement, interpreted as relative weights. Reliability and experience SHALL NOT receive combined-score weights. Organization/project management SHALL NOT accept customer-provided weight overrides in this release. Project activation SHALL retain the effective application weight values with the frozen configuration; subsequent default-weight changes SHALL NOT silently reweight active projects. Organization/global assessments SHALL retain their effective application-owned weight values and calculation provenance. A platform weight change for those scopes SHALL invalidate affected assessments and use the normal recalculation/publication path. Equivalent evidence, effective settings, and weight inputs SHALL produce the same result across reads, jobs, reports, and admission. Global calculation settings SHALL remain independent of organization/project configuration while shared source eligibility follows the broader-assessment contract. Adjustable customer weights are deferred; organization/global contributors and numerical settings SHALL use their own explicit defaults rather than inherit a source project's configuration.

#### Scenario: Application weights change after project activation
- **WHEN** developers change the central weight definition
- **THEN** new project activations use the new weights while already-active projects retain their frozen values, and rebuilt results remain attributable to the effective inputs used

#### Scenario: An organization attempts to override weights
- **WHEN** an authorized manager supplies score weights through organization or project configuration
- **THEN** the unsupported override is rejected rather than changing the calculation or global reputation

### Requirement: Answer quality uses a normalized weighted average
Each established quality contributor SHALL supply a rate between zero and one: correct divided by evaluated known-answer answers, effective human accepts divided by substantive human-reviewed answers, or agreements divided by eligible peer comparisons. For a nonempty selected contributor set S whose members all meet their configured minima, combined answer quality SHALL equal `100 * sum(weight[s] * rate[s] for s in S) / sum(weight[s] for s in S)`, using its retained positive effective relative weights. Thus deliberately unselected contributors SHALL be excluded before normalizing the remaining weights, and a single selected established contributor SHALL supply the whole quality score. Calculation SHALL use the underlying rates rather than display-rounded percentages. Supporting counts and the selected contributor set SHALL remain visible; the numeric score SHALL NOT imply evidence from excluded contributors.

An enabled selected contributor below its minimum SHALL make combined quality unavailable under the existing insufficient-evidence rules, without supplying a zero/success value or redistributing its weight. Known-answer precedence SHALL continue to prevent designated checks from also contributing peer-scored evidence. Reviewer-only peer agreement SHALL remain eligible for authorized reviewer summaries but excluded from automatic access calculations and their minimum-evidence requirements. Reliability and experience SHALL remain outside this combination.

#### Scenario: Known answers and peer agreement are selected
- **WHEN** human review is unselected, nineteen of twenty known answers are correct, twenty-four of thirty eligible peer comparisons agree, and the initial project weights and minima apply
- **THEN** reviewer-summary quality is `(60 * 0.95 + 10 * 0.80) / 70 * 100`, approximately 92.9%, with both sample counts retained and no human-review requirement

#### Scenario: All three quality contributors are selected
- **WHEN** eighteen of twenty known answers are correct, sixteen of twenty substantive human reviews accept, twenty-one of thirty eligible peer comparisons agree, and the initial weights and minima apply with all three selected for the summary
- **THEN** reviewer-summary quality is 85%, using sixty/thirty/ten relative weights without adding reliability or experience points

#### Scenario: Only known-answer correctness is selected
- **WHEN** eighteen of twenty known answers are correct under the initial project minimum and human review and peer agreement are unselected
- **THEN** combined quality is 90%, with neither excluded contributor treated as missing evidence

#### Scenario: A perfect known-answer sample is too small
- **WHEN** known answers and peer agreement are selected under the initial project minima, two of two known answers are correct, and twenty-seven of thirty eligible peer comparisons agree
- **THEN** combined quality is unavailable because the known-answer sample is below twenty, while actual counts and established peer evidence remain inspectable

#### Scenario: Peer agreement has too few worker observations
- **WHEN** known answers and peer agreement are selected under the initial project minima, nineteen of twenty known answers are correct, and nine of ten eligible peer comparisons agree
- **THEN** combined reviewer quality is unavailable because the peer worker sample is below thirty, without reweighting the summary to known answers alone or adding the reviewer-only peer minimum to automatic admission

### Requirement: Disabled and insufficient signals have distinct scoring outcomes
A scoring signal disabled by the effective configuration SHALL be not applicable and contribute neither a value nor weight to the combined calculation. Each combined result SHALL identify its contributing signal set; an admission result SHALL exclude reviewer-only signals and their minimum-evidence requirements. An enabled contributing signal with insufficient evidence SHALL remain in the insufficient-evidence state; it SHALL NOT receive a zero/success value or have its weight silently redistributed among established signals. A combined score SHALL be established only when every contributing enabled signal meets its minimum. Otherwise the combined numeric score SHALL be unavailable while individual established metrics and all applicable counts remain inspectable. A configuration with no contributing signals SHALL yield a not-applicable combined result. Established individual signals SHALL remain eligible for their own configured actions without waiting for unrelated signals. Insufficient combined admission evidence SHALL follow the existing project-local insufficient-evidence and established organization/global entry rules.

#### Scenario: Human-review scoring is disabled
- **WHEN** the effective configuration disables human-review scoring and all other contributing signals have sufficient evidence
- **THEN** the combined score is calculated from the selected signals without including human review as a zero or missing requirement

#### Scenario: Human-review scoring is enabled but has too little evidence
- **WHEN** known-answer accuracy is established but an enabled contributing human-review signal has not met its minimum
- **THEN** known-answer accuracy remains inspectable and eligible for its configured action, while the combined score has insufficient evidence with no usable numeric value

#### Scenario: No scoring signals are selected
- **WHEN** the effective configuration contains no contributing scoring signals
- **THEN** the combined result is not applicable rather than zero or perfect reputation

### Requirement: Human review is supplementary worker evidence
Initial project, organization, and global reputation defaults SHALL leave human-review scoring unselected. Authorized organization defaults or draft-project overrides SHALL be able to explicitly select it for their respective scopes; project selection SHALL follow the existing activation-freezing contract. Unselected human review SHALL contribute neither a value, weight, nor minimum-evidence requirement to combined quality, while authoritative review decisions and their actual counts SHALL remain retained and available to authorized readers. Platform-controlled global settings SHALL select eligible human-review evidence independently; a local omission SHALL NOT change the global calculation or erase source review history.

Human-review quality SHALL use only the assessed worker's eligible answers with effective substantive human accept/reject decisions within the declared scope and history window. Unreviewed answers and automatic acceptances SHALL contribute neither successes, failures, nor observations toward its minimum. Authorized worker summaries SHALL identify the reviewed-answer count, effective accept/reject counts, scope, window, and evidence state. The acceptance rate SHALL describe the reviewed answers rather than imply that every submission was evaluated. A configured minimum SHALL be an evidence requirement for establishing the metric, not a requirement to review that many answers per worker. An explicitly selected contributor below its minimum SHALL follow the existing insufficient-evidence rules rather than have its weight silently redistributed.

Project-wide or batch-wide review samples and acceptance rates SHALL NOT be assigned to individual workers or substitute for their own eligible evidence. Sparse or absent local review evidence SHALL NOT by itself establish poor quality. If no selected quality contributor is established, reliability, experience, and eligible broader assessments SHALL remain separately inspectable under their existing scope and authorization rules. Review sampling and budget management SHALL remain a future review capability; reputation SHALL NOT create review quotas, issue verdicts for unreviewed answers, or change the existing automatic/manual review lifecycle.

#### Scenario: Sparse reviews do not add a default quality requirement
- **WHEN** human-review scoring is unselected by default, known-answer correctness is established, and a worker has only two substantive reviews
- **THEN** the combined result follows its selected contributors without waiting for more human reviews, while those two decisions and their actual counts remain inspectable

#### Scenario: Human review evaluates only the sampled answers
- **WHEN** human-review scoring is selected, nineteen of a worker's twenty human-reviewed answers are accepted, the configured minimum is met, and another three hundred eighty answers have no substantive human review
- **THEN** the human-review metric is 95% from nineteen accepted and one rejected answer, with twenty observations; the other answers contribute no human-review success, failure, or minimum-evidence credit

#### Scenario: A pooled review sample does not establish every worker's quality
- **WHEN** reviewers inspect one hundred responses across three hundred workers and some workers have no reviewed responses
- **THEN** each worker's human-review count reflects only their own eligible reviewed answers; the sample's acceptance rate is not copied to unreviewed workers, and workers with selected human-review scoring below its minimum retain insufficient evidence

#### Scenario: Local omission preserves broader evidence
- **WHEN** a project omits human-review scoring and the worker has eligible human-review history contributing to a platform-controlled global assessment
- **THEN** the local omission does not remove that source history or reconfigure the independent global assessment

### Requirement: Review and task facts retain their meaning
Assessments SHALL derive from authoritative submitted answers, attempts, known-answer keys, and review evidence. Automatic acceptance of submitted answers SHALL NOT count as independent evidence of correctness. Human-review evidence SHALL retain its effective verdict and provenance; a rejection SHALL NOT be treated as an answer key. Skips SHALL remain distinguishable and SHALL NOT automatically reduce quality. Reputation SHALL NOT rewrite worker answers, issue review verdicts, select canonical answers, change submission targets, create replacement demand, or reopen satisfied tasks.

History windows SHALL select inputs for a calculation, not define source-data retention. Excluding evidence from a window SHALL NOT delete submitted answers, review history, or retained key history.

#### Scenario: Automatic review accepts every answer
- **WHEN** an automatically reviewed project accepts a worker's submissions
- **THEN** those acceptances do not increase substantive human-review quality or substitute for known-answer grading

#### Scenario: A quality concern follows task completion
- **WHEN** reputation detects repeated disagreement after a task reaches its submission target
- **THEN** the task stays satisfied and its responses, review verdicts, and sealed exports remain unchanged

#### Scenario: A calculation uses only part of the stored history
- **WHEN** a history window selects twenty observations from a larger stored history
- **THEN** only the selected observations enter that calculation while the unselected source evidence remains stored and unchanged

### Requirement: Known-answer checks bind to exact task evidence
Authorized organization managers SHALL be able to include known-answer checks among ordinary project work. Each key SHALL identify the exact published question, task, immutable revision inputs, and relevant option or input identities. A key SHALL NOT apply to every instance of a reusable form question merely because its question identity matches. Initial supported checks SHALL use the typed single-choice, multiple-choice, ranking, boolean, and numeric matching contract below. Unsupported grading families SHALL be rejected explicitly rather than silently scored; semantic free-text and spatial grading SHALL remain unsupported until separately specified.

#### Scenario: A question is reused for different inputs
- **WHEN** two tasks use the same published question with different immutable inputs
- **THEN** a key for one task does not grade the other task

#### Scenario: Presentation order is randomized
- **WHEN** the worker selects an input displayed in a different position from the author's presentation
- **THEN** grading compares the stable option/input identity rather than an A/B label or position

#### Scenario: A numeric answer is within tolerance
- **WHEN** a numeric answer is within the key's configured tolerance
- **THEN** it passes that check and the evaluated tolerance is retained with the grading provenance

#### Scenario: An unsupported key is supplied
- **WHEN** an author requests semantic free-text or spatial grading without an implemented grading contract
- **THEN** key authoring fails with a scoped validation error and creates no scoreable check

#### Scenario: Many workers answer one keyed question
- **WHEN** three hundred distinct workers submit evaluable answers to the same keyed task/question/input contract through its configured ordinary allocation capacity
- **THEN** the same applicable key grades each answer without requiring three hundred human review decisions, changing submission demand, or promising that every worker encounters other keyed questions

### Requirement: Known-answer authoring respects the project lifecycle
Initial key creation and check designation SHALL require current scoped `projects.manage` authority and a draft owning project. The operation SHALL recheck state and the exact authored task/question/input contract under the Project lock, serializing with activation and draft task removal. Activation SHALL validate all retained keys against the final authored contract. Once activated, a project SHALL accept only the existing-key correction, disabling, and re-enabling operations; it SHALL NOT acquire a new key or check designation, including for previously submitted ordinary answers.

Removing a draft task referenced by a retained key or key revision SHALL fail with a scoped validation explanation before deleting the task or its inputs. Disabling its key SHALL NOT remove that retained reference or permit deletion. Tasks without retained keys SHALL keep ordinary draft removal behavior. Key history SHALL NOT be cascaded away or detached from its exact task evidence to make removal succeed.

#### Scenario: Initial key creation races activation
- **WHEN** authorized initial key creation competes with activation
- **THEN** either creation commits first and activation validates/freezes that designation, or activation commits first and creation is rejected without changing frozen work

#### Scenario: An ordinary submitted question receives a proposed new key
- **WHEN** a manager attempts initial key creation after activation, including after responses exist
- **THEN** creation fails without changing that question's peer eligibility or adding retroactive known-answer grading; authorized changes to existing keys remain available

#### Scenario: A keyed draft task is removed
- **WHEN** a manager removes a draft task referenced by a retained key, including a disabled key
- **THEN** removal fails with a scoped explanation and preserves the task, inputs, key, and revision history; unkeyed draft tasks remain removable

### Requirement: Known-answer evidence reflects actual evaluated answers
A known-answer check SHALL mean a question with an organization-supplied expected answer for its exact task inputs. Such questions SHALL follow ordinary task allocation and submission capacity; this release SHALL NOT guarantee a check frequency or minimum number of checks for each worker. Authorized assessment reads SHALL report each worker's actual evaluated known-answer count, its configured minimum, and whether that minimum is met. Skipped and disabled checks SHALL NOT count as evaluated successes or failures. When known-answer scoring is enabled, exhaustion of authored checks or insufficient observations SHALL leave the signal in the insufficient-evidence state and SHALL NOT itself trigger a poor-quality suspension. Insufficient project-local history SHALL permit participation, without bypassing a separately configured requirement for established organization/global evidence or any other valid access restriction. Reports SHALL NOT imply that every worker was tested merely because the project contains known-answer questions.

#### Scenario: Earlier workers consume the available known-answer tasks
- **WHEN** known-answer scoring is enabled and ordinary allocation satisfies those tasks before another worker encounters them
- **THEN** the later worker's known-answer count remains zero and the signal has insufficient evidence, without a fabricated score or a failure-based suspension

#### Scenario: A worker sees questions but does not produce evaluable answers
- **WHEN** a worker skips known-answer questions or their evaluations are excluded
- **THEN** those observations do not satisfy the evaluated-answer minimum and the assessment reports the actual eligible count

### Requirement: Organizations can inspect known-answer evidence and question quality
Organization reviewers with `tasks.review` SHALL have scoped worker reports showing evaluated known-answer count, correct and incorrect counts, accuracy when the evaluated count is nonzero, configured minimum, and whether that minimum is met. Worker reports SHALL use the worker assessment's configured history window and identify its configuration, key provenance, evaluation cutoff, and freshness. Reports SHALL reuse the assessment's evidence state: disabled/unselected scoring SHALL be not applicable, while enabled scoring below its minimum SHALL have insufficient evidence. A zero count alone SHALL NOT determine that state or make a disabled signal appear to have an unmet minimum.

Question-quality reports SHALL instead be calculated on demand from one coherent read snapshot of the exact task/question/input contract, its current key revision and enabled state, submitted answers, and server report cutoff. They SHALL summarize all evaluable submitted answers through that cutoff, independently of workers' reputation windows and reinstatement cutoffs, and report evaluated, correct, and incorrect counts and match rate when evaluable answers exist. They SHALL identify the captured key revision, enabled state, all-history sample, and cutoff; a report SHALL NOT mix key revisions or claim currency beyond its captured cutoff. Corrections and enabled-state changes committed before capture SHALL be reflected by the next report request without waiting for worker-assessment recalculation. Changes after capture SHALL NOT alter that response's fixed snapshot. These reports SHALL have no persisted completed-report projection, report refresh jobs, pending-report lifecycle, or configurable report window. Work on other questions or the passage of a worker's history-window boundary SHALL NOT remove answers from this question's sample. Worker reports SHALL retain their completed-assessment freshness and pending-update behavior.

Skipped and disabled evaluations SHALL NOT enter current accuracy denominators. A zero denominator SHALL yield unavailable accuracy rather than a success or failure rate, and enabled scoring with insufficient worker history SHALL retain its insufficient-evidence status. Question outcome summaries SHALL be diagnostic: widespread failure alone SHALL NOT declare a key invalid, disable it, pause a project, or add an automatic worker restriction. When reviewer investigation warrants a key change, an actor with `projects.manage` SHALL use the authorized key correction/disabling/re-enabling and recalculation actions. These reports SHALL NOT require extra worker interactions, change reputation windows or source retention, or disclose protected evidence to workers.

#### Scenario: Perfect accuracy has little supporting evidence
- **WHEN** one worker answers eighteen of twenty known-answer questions correctly and another answers two of two correctly within their assessment windows
- **THEN** reviewers see both counts and the corresponding 90% and 100% accuracy, together with each worker's minimum-evidence status

#### Scenario: Enabled known-answer scoring has no evaluated responses
- **WHEN** known-answer scoring is enabled and the organization reads a worker's report with no evaluated known-answer responses
- **THEN** it shows zero evaluated answers, unavailable accuracy, and insufficient-evidence history rather than implying that the worker passed or failed

#### Scenario: Known-answer scoring is disabled
- **WHEN** the organization reads a worker's report under a configuration that disables known-answer scoring
- **THEN** the report reuses the assessment's not-applicable state without presenting an unmet minimum, including when the evaluated count is zero

#### Scenario: Most workers disagree with a supplied key
- **WHEN** only ten of one hundred eligible evaluated responses match a question's key
- **THEN** authorized reviewers can inspect the counts and 10% match rate to investigate the key or instructions, without the report automatically changing the key, project state, or worker restrictions

#### Scenario: Workers move on to later questions
- **WHEN** two of ten answers match a question's key and those workers later answer enough other questions to move the original answers outside their reputation windows
- **THEN** the question report still shows two of ten matching that key, while worker reports follow their own windows and all source answers remain stored

#### Scenario: A key correction changes the question report
- **WHEN** a corrected key changes which stored answers match
- **THEN** the next question-report request evaluates the same all-history sample under the corrected key without waiting for assessment refresh, identifies its revision, and does not mix old and new grades or restore expired answers to worker reputation windows

#### Scenario: A key changes during report calculation
- **WHEN** a question report captures revision three and a correction commits revision four after its snapshot begins
- **THEN** that response consistently identifies and uses revision three as of its cutoff, and a subsequent request captures revision four without a report publication or repair job

#### Scenario: The captured key is disabled
- **WHEN** a question-report request captures a disabled key
- **THEN** it identifies that revision and disabled state, reports no evaluated successes or failures and unavailable accuracy, and does not reuse grades from a formerly enabled report

### Requirement: Reviewers can list current reputation concerns and inspect worker detail
Organization reviewers with `tasks.review` SHALL have bounded paginated project reputation queries under the [operation mapping](#requirement-reputation-operations-fail-closed-within-organization-scope). Each query SHALL declare its owning organization and project and return at most one row per related worker in that project, grouping the worker's current concerns rather than emitting a new alert for every answer or recalculation. Worker relationships SHALL come from retained ordinarily authorized work requests or performed work in that project; ordinary membership or an arbitrary User identity SHALL NOT create reputation browsing authority.

The list SHALL support filters for workers with established metrics below applicable configured thresholds, workers with insufficient evidence, and workers with returns awaiting classification. Insufficient/disabled/not-applicable metrics and unfinished preliminary peer comparisons SHALL NOT become below-threshold quality concerns. An awaiting-review return SHALL remain separately visible without counting as a confirmed reliability failure or satisfying the eligible-attempt minimum. A worker MAY appear in more than one filter because different metrics or return states apply.

Worker detail SHALL identify each concern's metric, supporting eligible counts, unrounded rate/score with sufficient presentation precision, applicable threshold, configured action, and declared evidence scope/history. It SHALL expose calculation cutoff, supporting original observation dates, pending-refresh metadata, and permitted supporting evidence and retained source/correction/access-decision history. Broader inputs SHALL retain their assessed scope and the [bounded global disclosure contract](#requirement-global-summary-disclosure-requires-an-organization-work-relationship); the project list SHALL NOT expose other organizations' evidence or reconfigure their assessments. All list/detail reads SHALL recheck current scoped authority without broadening worker or general source-read access.

Current concerns SHALL follow the latest completed applicable calculation and rule configuration. A pending update SHALL remain labeled and SHALL NOT fabricate a new concern or silently clear an existing one. Once a completed calculation no longer supports a concern, that concern SHALL disappear from the current list/filter without deleting its supporting source or decision history. Reads SHALL derive current concerns from completed assessment inputs and ordinary configured rules, rather than add an independently managed concern lifecycle or duplicate event stream. Reviewer-only concerns SHALL remain informational with their existing admission exclusions; list filters and detail reads SHALL NOT change work access, source evidence, or return classifications.

Delivery in this change SHALL be through the scoped backend queries for organization applications to display. Reputation email/webhook notifications and acknowledgment, dismissal, or escalation workflows SHALL remain outside this change. No frontend or notification subsystem SHALL be required to make the reviewer information available.

#### Scenario: A worker has several current concerns
- **WHEN** a project's applicable rules identify established correctness and peer-agreement concerns for the same worker
- **THEN** its paginated list contains one worker row with both concerns, and detail exposes their respective counts, thresholds, actions, scopes, and freshness rather than duplicate worker alerts

#### Scenario: Worker agreement falls below the initial reviewer threshold
- **WHEN** a reviewer-only agreement rule has twenty-three agreements across thirty eligible comparisons under its initial eighty-percent threshold
- **THEN** the worker's row/detail shows approximately 76.7 percent agreement, twenty-three of thirty, the eighty-percent threshold, and reviewer-only action without restricting work

#### Scenario: Few comparisons are insufficient rather than poor quality
- **WHEN** a worker has five peer comparisons under the initial thirty-comparison minimum and no other established below-threshold metric
- **THEN** the worker is available through the insufficient-evidence filter without a poor-quality concern or inclusion in the below-threshold filter

#### Scenario: A return awaits reviewer classification
- **WHEN** a worker has a released attempt whose effective classification is awaiting review
- **THEN** the worker is available through the awaiting-classification filter and the permitted return detail remains inspectable, without treating that return as an unexcused reliability outcome

#### Scenario: A completed update resolves a concern
- **WHEN** a worker has a current below-threshold concern and a replacement completed calculation no longer supports it
- **THEN** the current concern/filter entry clears while retained source and decision history remain inspectable; while that replacement is merely pending, the previous completed concern remains labeled with its pending update

### Requirement: Keys and check designations remain private
Worker presentation SHALL use the ordinary question/input contract without disclosing the answer key or the designation of a question as a quality check. Worker-facing APIs, nested GraphQL traversal, errors, and work-access outcomes SHALL NOT reveal hidden keys, other workers' answers, or another organization's private evidence. A worker account SHALL NOT gain manager access by holding an attempt. Organization reviewers with `tasks.review` SHALL be able to inspect supporting own-organization evidence, including relevant keys/history, under the [explicit operation mapping](#requirement-reputation-operations-fail-closed-within-organization-scope). Managers with `projects.manage` SHALL be able to inspect scoped keys/history for management without gaining general reputation-report or submitted-answer access. Detailed worker-facing reputation explanations and dispute workflows are deferred; organization reviewer evidence and recovery actions remain in scope.

Authorized key authors/readers who also perform work SHALL follow the ordinary reputation evidence rules. Prior key knowledge alone SHALL NOT exclude their answers or prohibit an otherwise authorized key edit. No key-disclosure tracking or special reveal workflow is required. Existing organization authorization, key-change attribution, and human-review rules remain effective.

#### Scenario: An external worker inspects a work bundle
- **WHEN** an eligible external worker reads a task containing a known-answer check
- **THEN** ordinary task content is available without organization membership, while check designation, key, and manager-only relationships remain inaccessible

#### Scenario: A worker follows nested relationships
- **WHEN** a worker requests key data or other workers' answers through an attempt, task, question, or assessment relationship
- **THEN** the request grants no access to that protected evidence

#### Scenario: A key author also performs work
- **WHEN** an otherwise eligible user who authored a key submits an evaluable answer to that question
- **THEN** the answer follows ordinary grading and reputation rules without an exclusion based on authorship

### Requirement: Key corrections preserve history and repair assessments
Authorized corrections, disabling, or explicit re-enabling of an existing key SHALL retain the prior key, matching rule, enabled/disabled state, actor, reason, and evaluation provenance. An ordinary correction SHALL preserve the key's enabled/disabled state; correcting a disabled key SHALL NOT silently resume grading. An authorized manager with `projects.manage` SHALL be able to explicitly re-enable an existing corrected key. Corrections and enabled-state changes SHALL use the same retained history and recalculation workflow without mutating submitted answers. Re-enabling SHALL restore eligible grading under the current key and existing scope/window rules, preserving each answer's original observation identity and submission time. Repeated action requests SHALL NOT duplicate transitions or contributions. Each correction or enabled-state change SHALL cause affected assessments and reputation restrictions to be reevaluated; obsolete evaluations SHALL NOT remain effective after recalculation or overwrite a newer result. Review corrections SHALL likewise feed recalculation. Reviewers SHALL have evidence to identify widespread key failures and investigate potentially incorrect keys or instructions.

Each correction, disabling, or re-enabling request for an existing key SHALL require a nonblank explanation, the expected current key-revision identity viewed by the manager, and a caller-supplied UUID request key. All three operations SHALL share the same ordered key/matching-rule/enabled-state history: a valid change SHALL append a retained successor to the expected current revision, and that successor SHALL become effective. A new request with an obsolete expected revision SHALL conflict without changing the effective key, history, or recalculation inputs. Concurrent requests against the same current revision SHALL permit one valid successor; another manager SHALL inspect the newer revision before deliberately retrying with a fresh request key.

Request keys SHALL be scoped to the exact known-answer key and requesting actor. Every operation, including replay, SHALL recheck current active account, owning organization, active membership, and `projects.manage` authority. After current authorization, an identical successful replay SHALL be recognized before checking its now-obsolete expected revision and SHALL return the original retained result without another append, duplicate reputation evidence, or reapplication of that change. Replaying an earlier result after a later correction/state change SHALL leave the latest effective revision unchanged. Different request content under the same scoped key SHALL conflict. Invalid UUIDs, blank explanations, missing/foreign expected revisions, and failed authority SHALL produce no partial change.

Revision/predecessor validation, current authorization, the history append, and the corresponding recalculation invalidation/scheduling facts SHALL be coherent with the committed key change. This SHALL preserve the existing correction-state rule: a correction of a disabled key SHALL remain disabled, and a stale correction SHALL NOT overwrite a newer disabling or re-enabling. Concrete guard storage and lock ordering SHALL follow the shared publication/allocation design rather than create a separate key-recovery lifecycle.

#### Scenario: Two managers correct the same key revision
- **WHEN** Alice and Bob both inspect revision three and submit valid corrections expecting that revision, and Alice's correction commits as revision four first
- **THEN** Bob's new request conflicts without another append or overwriting revision four; he must inspect that revision before submitting a deliberate correction with a fresh request key

#### Scenario: A successful correction is retried after another change
- **WHEN** a manager successfully corrects revision three to revision four, a later authorized change creates revision five, and the manager identically retries the earlier successful request under current authority
- **THEN** the replay returns its original revision-four result before checking the old expectation, while revision five remains effective and no correction or reputation observation is duplicated

#### Scenario: A correction races key disabling
- **WHEN** a correction and a disabling request both expect the same revision and disabling commits first
- **THEN** the stale correction conflicts without re-enabling the key; a deliberate correction of the newly disabled revision preserves its disabled state

#### Scenario: Key-change input or replay authority is invalid
- **WHEN** a change has a blank explanation, invalid UUID, missing/foreign expected revision, or changed content under an existing scoped request key, or a replay loses current management authority
- **THEN** it fails without appending history, changing the effective key, or partially changing recalculation inputs

#### Scenario: A wrong expected answer penalizes workers
- **WHEN** an authorized manager corrects or disables that key
- **THEN** its old evaluation remains explainable, affected assessments are recalculated, and restrictions based on the faulty evidence are reevaluated without editing submissions

#### Scenario: A stale recalculation finishes later
- **WHEN** a calculation using an older key or review finishes after a calculation using its correction
- **THEN** it cannot restore the obsolete assessment or restriction

#### Scenario: A disabled key is corrected
- **WHEN** an authorized manager corrects a disabled key's expected answer or matching rule
- **THEN** the correction is retained while the key remains disabled and contributes no current known-answer grading

#### Scenario: A corrected key is explicitly re-enabled
- **WHEN** an authorized manager re-enables an existing corrected key
- **THEN** the attributed state change triggers normal recalculation using the current key and eligible stored answers, preserving original observation identities and submission times rather than duplicating contributions or making old answers recent

### Requirement: Supported answer matching uses typed values
Known-answer grading and peer comparison SHALL share matching semantics for supported answer families without changing their different evidence sources. Single-choice answers, including pairwise and image-choice renderers, SHALL match by the same canonical selected option or task-input identity, not display text or position. Multiple-choice answers SHALL match only when their complete sets of selected identities are equal, ignoring selection order; missing or additional selections SHALL fail that match. Ranking answers SHALL match only when the complete ordered sequences of input identities are equal. Boolean answers SHALL match by their actual true/false value; false SHALL NOT be confused with an absent answer. Initial supported comparisons SHALL award no partial credit for overlapping selection sets or similar rankings. Authored expected answers SHALL satisfy the pinned question's typed constraints, cardinality, and exact task-input references.

Integer and decimal matching SHALL use absolute numeric tolerance D, which SHALL be finite and nonnegative and default to zero for exact matching. Values SHALL match when their absolute difference is less than or equal to D, including both boundaries. Comparison SHALL use numeric values with preserved decimal precision rather than formatted strings, display rounding, or percentage distance. A known-answer key SHALL retain its own expected value and tolerance with its grading provenance. Numeric peer tolerance SHALL come from the assessed scope's effective settings, independently of a key's tolerance or another scope's settings. Correcting a key SHALL use the existing retained history and affected-scope repair contract; changing organization/global peer settings SHALL use ordinary recalculation while frozen project settings remain unchanged.

Numeric peer comparison SHALL calculate the median of all eligible distinct other-worker answers after the existing self/dedup/skip exclusions. For an even count, the median SHALL be the arithmetic mean of the two middle numeric values, preserving decimal precision even for integer responses. A numeric consensus SHALL exist only when coverage and completed-task eligibility are met and at least the configured consensus fraction of all eligible other values lies within the inclusive interval from median minus D through median plus D. Initial consensus SHALL require at least eighty percent. If that concentration is insufficient, the comparison SHALL supply neither agreement nor disagreement nor worker minimum-evidence credit. If sufficient, an assessed worker's numeric answer SHALL agree exactly when it is within the same inclusive interval. Calculating a median SHALL NOT by itself establish consensus, manufacture a known-answer key, select a canonical collected answer, or rewrite submitted values. Each eligible comparison SHALL continue to contribute at most one worker observation.

Semantic free-text and spatial matching SHALL remain unsupported in this change until their separate grading contracts are specified. A spatial answer SHALL NOT be scored by exact coordinate/pixel equality or by reusing numeric scalar tolerance. The [future spatial-grading capability](../../../../future-features.md#spatial-grading-for-bounding-boxes-and-segmentation) SHALL define its own annotation comparison before reputation consumes its outcomes.

#### Scenario: Multiple selections differ only in order
- **WHEN** one answer selects A and B and the reference or eligible peer answer selects B and A using the same canonical identities
- **THEN** the multiple-choice sets match, while A alone or A/B/C does not match A/B

#### Scenario: Rankings contain the same items in a different order
- **WHEN** the expected or consensus ordering is A/B/C and the worker submits B/A/C
- **THEN** the ranking does not match and supplies no partial match credit merely because its item set is equal

#### Scenario: A numeric answer lies on a tolerance boundary
- **WHEN** a numeric key expects one hundred with absolute tolerance two
- **THEN** ninety-eight and one hundred two match inclusively, while ninety-seven and one hundred three do not

#### Scenario: Numeric formatting differs under exact matching
- **WHEN** two valid decimal values represent one hundred and one hundred point zero under zero tolerance
- **THEN** their numeric values match without string comparison or display rounding

#### Scenario: An even peer count has a fractional median
- **WHEN** a completed eligible comparison's two integer peers answer ten and eleven with peer tolerance one
- **THEN** the median is ten point five, both peers fall within its inclusive band, and the median remains an internal comparison center rather than a replacement integer answer

#### Scenario: A median does not establish numeric consensus
- **WHEN** eligible peers split evenly between zero and one hundred with tolerance two
- **THEN** the median is fifty but no peer is within its tolerance band, so the comparison supplies no scored observation despite having a calculable median

### Requirement: Peer comparison requires sufficient comparable evidence
Peer agreement SHALL compare submitted answers from distinct workers to the same question and exact task inputs under the same pinned contract. It SHALL exclude the assessed worker's answer, duplicate votes from one peer, skips, and absent answers. A comparison SHALL contribute only when the response-count-dependent peer minimum and consensus threshold are met. Ties, sparse evidence, and split opinion SHALL contribute neither scored agreement nor disagreement nor worker minimum-evidence credit. Identity comparisons SHALL use canonical option/input identities; supported numeric comparisons SHALL use a robust center and configured tolerance.

Eligible answers SHALL be valid answered QuestionResponses from successfully submitted attempts under that pinned contract. Saved drafts and unfinished/unsubmitted outcomes SHALL NOT qualify. Peer eligibility and vote weight SHALL be independent of review state: awaiting review, automatic acceptance, effective human acceptance, and effective human rejection SHALL follow the same submission-based rules in project, organization, and global assessments. This SHALL apply to both peer answers and the assessed worker's answer. A human rejection SHALL remain separate substantive human-review evidence and SHALL NOT remove or reduce that answer's peer participation. Review-only decisions/corrections SHALL NOT change the peer population, coverage, consensus, or peer grades, and SHALL NOT require recalculation of other workers' peer comparisons. Human-review inputs and dependent assessment results SHALL refresh through their ordinary correction path. Known-answer precedence, source-project agreement exclusions, completed-task eligibility, deduplication, and the configured coverage/consensus safeguards SHALL remain effective.

For each comparison, T SHALL be the source task's frozen submission target, including the assessed worker. With peer count floor F and peer coverage fraction P from the assessed scope's effective settings, the minimum eligible other-worker count SHALL be `max(F, ceil(P * (T - 1)))`. Initial project, organization, and global defaults SHALL set F to two, P to eighty percent, and the separate consensus threshold to eighty percent. The floor SHALL be at least two and the coverage fraction SHALL be positive and no greater than one. The consensus percentage SHALL be finite, greater than fifty, and no greater than one hundred in every assessment scope; this SHALL retain the initial eighty-percent setting and allow a stricter unanimity requirement. Coverage SHALL use the requested count rather than the number of non-skipped answers observed, so widespread skips cannot lower its denominator. Organization/global comparisons SHALL use each source task's T with their own effective peer parameters, not the target of a new project requesting broader reputation or the pooled scope's observation count. Project parameters SHALL be frozen at activation; organization parameters SHALL follow its current settings and global parameters SHALL remain platform-controlled.

Once coverage is met and the source task has reached its frozen target, consensus SHALL use all eligible distinct other-worker answers, not a selected subset equal to the minimum. For exact single-choice, multiple-choice, ranking, and boolean comparisons, a common complete typed answer SHALL meet the consensus threshold inclusively; at the initial threshold, at least eighty percent of those actual eligible answers SHALL match under the supported answer-matching contract. Coverage and consensus SHALL remain separate inputs and SHALL NOT silently change together when one is overridden. Numeric matching and concentration SHALL use that same contract's median and inclusive absolute-tolerance rules while preserving the coverage boundary. A skipped or absent assessed answer SHALL produce no scored comparison.

Each eligible assessed-worker answer to one exact task/question/input contract SHALL contribute at most one peer observation per assessment scope, regardless of the number of peers. The initial thirty-comparison worker minimum SHALL therefore require thirty eligible question comparisons, not thirty pairwise votes from one question. Initial targets of one or two SHALL supply no scored peer comparison because they cannot meet the two-peer floor. Missing coverage or consensus SHALL leave the comparison unavailable without treating a skip as failure, creating replacement work, increasing the submission target, or converting unfinished comparisons into scored evidence.

#### Scenario: Mixed human-review outcomes retain submitted peer answers
- **WHEN** a completed task with target ten has nine eligible other-worker answers to an ordinary unkeyed question, eight selecting A and one selecting B, with some pending human review, some manually accepted, and some manually rejected
- **THEN** all nine remain in the peer population, coverage and eight-of-nine consensus are met under the initial parameters, and the assessed worker's answered response agrees exactly when it selects A
- **AND** each actual human decision remains evidence only for the worker whose answer was reviewed; it does not assign review success/failure to unreviewed workers

#### Scenario: Review corrections preserve peer comparisons
- **WHEN** a human acceptance of a submitted answer is corrected to rejection, or a rejection is corrected to acceptance, without changing the submitted answer or pinned contract
- **THEN** its peer eligibility and vote weight remain unchanged in all assessment scopes, and other workers' peer comparison inputs, grades, and observation counts remain unchanged
- **AND** the reviewed worker's substantive human-review evidence and dependent results refresh normally while the prior decision and immutable submission remain retained

#### Scenario: Automatic acceptance supplies no extra peer authority
- **WHEN** an answered outcome is successfully submitted in automatic review mode
- **THEN** its submitted answer may supply its worker's ordinary single peer answer under the same eligibility rules as a pending manual-review answer, without an extra vote, higher weight, or substantive human-review success

#### Scenario: Coverage scales with requested responses
- **WHEN** the initial peer parameters apply to tasks with frozen submission targets of three, five, ten, thirty, and three hundred
- **THEN** their minimum eligible other-worker counts are respectively two, four, eight, twenty-four, and two hundred forty

#### Scenario: A small task supplies unanimous peers
- **WHEN** a task with target three reaches its target and both eligible other workers give the same choice answer
- **THEN** both coverage and the initial consensus threshold are met, and the assessed worker's answered response supplies one agreement or disagreement observation according to its match

#### Scenario: Too few peers answer a completed large task
- **WHEN** a task with target three hundred reaches its submission target but only two hundred thirty-nine eligible other workers answer the question under the initial parameters
- **THEN** coverage is not met and the comparison supplies neither agreement nor disagreement nor worker minimum-evidence credit, even if those answers are unanimous

#### Scenario: Coverage and consensus have different denominators
- **WHEN** a completed task with target ten has eight eligible other answers, six matching A and two matching B, under the initial parameters
- **THEN** coverage is met but the seventy-five-percent consensus is insufficient, so the comparison contributes no scored observation; seven matching A out of those eight would meet the consensus threshold

#### Scenario: Consensus uses all eligible peers
- **WHEN** a completed task with target ten has nine eligible other answers, seven matching A and two matching B, under the initial parameters
- **THEN** the comparison is unavailable because seven out of nine is below eighty percent, rather than selecting eight peers whose seven matching answers would meet it

#### Scenario: A large peer group supplies one worker observation
- **WHEN** a worker's answer meets the comparison conditions against two hundred ninety-nine eligible other answers
- **THEN** it supplies one peer observation for that worker rather than two hundred ninety-nine observations or automatic satisfaction of the thirty-comparison worker minimum

#### Scenario: The target cannot supply two other workers
- **WHEN** a task with target one or two completes under the initial parameters
- **THEN** no scored peer comparison is available, while other eligible reputation evidence and ordinary submitted-task counting retain their existing meanings

#### Scenario: The worker would create their own majority
- **WHEN** the assessed worker's answer would cause a label to pass the agreement threshold
- **THEN** that answer is excluded before deciding whether the peers establish a usable comparison

#### Scenario: Peer opinion is split
- **WHEN** other workers tie or do not reach the configured agreement threshold
- **THEN** the comparison supplies no negative signal for any worker

#### Scenario: Retry evidence is encountered during a rebuild
- **WHEN** the same peer's submission is encountered more than once
- **THEN** that peer contributes at most one vote to the comparison

#### Scenario: Small differing samples establish no consensus
- **WHEN** a completed comparison meets coverage but its two other workers disagree, or three of four eligible other answers match under the initial eighty-percent consensus
- **THEN** it supplies no scored agreement, disagreement, or worker minimum-evidence credit; two of two or four of five matching would meet the consensus fraction only if the independent coverage requirement is also met

### Requirement: Repeated disagreement is weaker than correctness
Disagreement assessments SHALL require a minimum worker sample and repeated comparable observations within the configured recent-history window. One unusual answer SHALL NOT establish consistently poor reputation. Agreement's scoring contribution SHALL be bounded and weaker than known-answer correctness. Projects SHALL be able to disable agreement scoring and enforcement when consensus does not represent quality. Conflicting strong correctness and unusual disagreement SHALL remain distinguishable to reviewers.

When agreement is disabled for subjective preference collection, differing opinions SHALL NOT contribute quality failures or restrictions. Authorized reviewers SHALL be able to inspect the differing submitted answers without reputation converting the majority preference into an answer key or an effective human-review verdict.

#### Scenario: A subjective preference project disables agreement
- **WHEN** its workers give differing opinions
- **THEN** those differences do not reduce reputation or trigger disagreement-based restrictions

#### Scenario: A minority preference follows the instructions
- **WHEN** agreement scoring is disabled for a preference project and a worker chooses a less popular image while providing the requested explanation
- **THEN** reputation does not infer a correctness failure or human rejection from the minority preference, and the submitted answer remains available to authorized reviewers

#### Scenario: A correct worker disagrees with peers
- **WHEN** a worker has strong known-answer accuracy and repeated peer disagreement
- **THEN** reviewers can see both signals and their sample counts instead of receiving an unexplained poor-quality label

### Requirement: Known-answer grading takes precedence over peer disagreement
A question designated as a known-answer check SHALL use its eligible known-answer evaluation rather than peer agreement as quality evidence for that answer. Peer disagreement on that question SHALL NOT contribute to a worker's score, peer sample minimum, or automatic restriction, even when disagreement enforcement is independently enabled. Authorized reviewers SHALL be able to inspect key-versus-peer conflicts as possible key, instruction, or peer-quality problems. Disabling a key SHALL remove its grading contribution without automatically converting the designated check into peer-scored evidence. Correcting a key SHALL recalculate its contribution and dependent restrictions under the same precedence rule.

#### Scenario: The majority gives the wrong answer to a known-answer question
- **WHEN** a worker matches the active key but other workers agree on a different answer
- **THEN** the worker receives the eligible known-answer outcome and no contradictory disagreement penalty or suspension from that question

#### Scenario: A questionable key is disabled
- **WHEN** an authorized actor disables a key after conflicting responses are found
- **THEN** its grading stops contributing and the same question does not become a new source of peer-based penalties

### Requirement: Unfinished peer comparisons cannot restrict work
Peer comparisons SHALL become eligible for reputation scoring and enforcement only when the task reaches its frozen submission target and the final distinct-peer sample satisfies the configured minimum and consensus threshold. Earlier comparisons SHALL be labeled preliminary and available only as authorized reviewer information; they SHALL NOT contribute to scores or admission/restriction decisions. Completing a project before a task meets its target SHALL NOT convert that partial comparison into enforceable evidence. A current assessment containing pending comparisons SHALL remain distinguishable from a stale calculation; unfinished evidence alone SHALL NOT cause indefinite allocation retries. Insufficient local history SHALL permit participation; separately configured established organization/global entry requirements SHALL still apply.

#### Scenario: An early majority reverses
- **WHEN** early submitted answers favor one option but the final submitted set favors another
- **THEN** the early comparison causes no score change or suspension, and only the completed eligible comparison contributes

#### Scenario: A project closes with a partially answered task
- **WHEN** completion cancels remaining capacity before the task's submission target is met
- **THEN** its peer comparison remains non-enforcing and collection is not reopened to obtain more answers

### Requirement: Reputation thresholds use inclusive minimums
Percentage thresholds for known-answer correctness, substantive human-review acceptance, worker peer agreement, combined answer quality, and reliability SHALL mean a minimum acceptable value: an established value greater than or equal to the configured threshold SHALL meet the requirement, and a lower value SHALL trigger only the rule's configured action. Percentage thresholds SHALL represent finite values from zero through one hundred inclusive. Comparisons SHALL use the underlying rate or score at an equivalent scale with precision preserved before display rounding. Reporting disagreement SHALL NOT reverse this rule: a peer rule SHALL compare the worker's agreement rate with its configured minimum agreement percentage.

Threshold evaluation SHALL first apply the assessed rule's existing selection, evidence eligibility, history, minima, and evidence-state requirements. Disabled/not-applicable and insufficient values SHALL NOT be treated as zero, passing scores, or established below-threshold failures. Combined quality SHALL retain its selected-contributor minima and reviewer-only admission exclusions. This boundary SHALL NOT bypass separately configured established organization/global entry requirements or change the existing project-local insufficient-history path. Reviewer-only concerns SHALL remain reviewer information; automatic action SHALL require the existing explicit eligible configuration and affect only new work in its project.

Experience entry requirements SHALL use an inclusive minimum integer count of eligible submitted answered questions in the declared scope/history: a count equal to or greater than N SHALL meet an at-least-N requirement. Configured experience minimums SHALL be positive integers under existing feasibility validation, and SHALL NOT contribute answer-quality points. Actual counts, including zero, SHALL remain reportable under the existing evidence-state rules. Supporting reports SHALL identify the applicable threshold, evidence counts/state, and enough score precision to explain a near-boundary decision rather than imply that rounded equality met it.

#### Scenario: Equality meets a quality requirement
- **WHEN** an established known-answer metric has eighteen correct answers out of twenty and a configured reviewer threshold of ninety percent
- **THEN** its exact ninety-percent rate meets the requirement and supplies no below-threshold concern; seventeen correct out of twenty would fall below that threshold and trigger the configured reviewer concern

#### Scenario: Display rounding cannot turn a concern into a passing score
- **WHEN** established reviewer-reported combined quality selects eighteen-of-twenty correctness and twenty-six-of-thirty peer agreement, excludes human review, uses the initial sixty/ten relative weights, and has a ninety-percent reviewer threshold
- **THEN** its unrounded quality is approximately 89.5238 percent and triggers the reviewer concern even if a presentation rounds it to ninety percent, with precision/counts explaining the result
- **AND** reviewer-only inputs still cannot affect automatic admission through that combined report

#### Scenario: A perfect insufficient sample cannot satisfy a threshold
- **WHEN** enabled known-answer correctness has two correct answers out of two under the initial twenty-answer minimum and a configured ninety-percent threshold
- **THEN** it remains insufficient without a threshold pass or established below-threshold failure, while actual counts and the existing local/broader admission rules remain available

#### Scenario: An experience requirement accepts its exact minimum
- **WHEN** a configured organization-history entry requirement asks for at least thirty eligible submitted answered questions
- **THEN** thirty questions meet that count requirement and twenty-nine do not, without changing answer quality or other admission rules

### Requirement: Configured rules have explicit starting thresholds
Configured reviewer/action and admission rules SHALL initially use the following minimum acceptable percentages under the [inclusive comparison contract](#requirement-reputation-thresholds-use-inclusive-minimums):

| Metric | Initial minimum |
| --- | --- |
| Known-answer correctness | 90% |
| Substantive human-review acceptance, when selected | 90% |
| Worker peer agreement | 80% |
| Combined answer quality | 90% |
| Reliability | 95% |

These SHALL be starting values for explicitly configured rules, including project entry rules that consult organization/global metrics, rather than new score-calculation inputs or automatic restrictions. Authorized organization defaults and draft-project overrides SHALL be able to adjust the bounded thresholds independently through ordinary configuration resolution and activation freezing. Project overrides SHALL NOT change independent organization/global calculation settings, and global settings SHALL remain platform-controlled. Human-review scoring SHALL remain unselected by default. The eighty-percent worker agreement minimum SHALL measure the worker's rate across eligible scored question comparisons, separately from the coverage and consensus percentages needed to make each question comparison eligible.

Each rule SHALL retain its evidence minimum, selected contributors, declared scope/history, reviewer-only admission exclusions, and configured action. No starting threshold SHALL select a signal, enable an automatic action, or introduce a platform-wide restriction. Experience SHALL have no default entry gate; any supported broader-history experience requirement SHALL explicitly choose its positive answered-question minimum. Existing active projects SHALL retain their prior frozen contracts.

#### Scenario: Initial reliability tolerates one failure among twenty eligible attempts
- **WHEN** a configured reliability rule uses its initial ninety-five-percent threshold and twenty-attempt minimum, with nineteen completions and one eligible expiration or confirmed unexcused return in its selected history
- **THEN** its established ninety-five-percent reliability meets the threshold; eighteen completions and two such outcomes establish ninety percent and trigger only the rule's configured action
- **AND** excused returns and returns awaiting review remain excluded from the scoring denominator and minimum, without disappearing from reviewer reports

#### Scenario: Initial worker agreement uses scored questions rather than the consensus vote
- **WHEN** a reviewer-only agreement rule has thirty eligible question comparisons, twenty-four of which agree with the established peers
- **THEN** its eighty-percent worker agreement meets the starting threshold without changing any question's separate coverage or consensus requirements, and fewer than twenty-four agreements would raise only the configured reviewer concern

#### Scenario: Starting values do not activate optional rules
- **WHEN** a project retains the starting thresholds without selecting human-review scoring, enabling an automatic action, or explicitly choosing an experience entry requirement
- **THEN** the ninety-percent human-review threshold creates no scoring requirement, the stored thresholds enable no automatic restriction, and answered-question counts remain reportable without a default experience gate

### Requirement: Signal actions support review and recoverable project suspension
Each enabled answer-quality signal and the separate reliability metric SHALL support a configured action to inform reviewers or suspend new project work after its minimum evidence and threshold conditions are met. Experience SHALL support reporting and explicitly configured broader-history entry requirements without becoming a weighted quality signal. Reviewer-only signals MAY contribute to authorized reviewer summaries, but SHALL NOT restrict work directly or indirectly through combined admission scores, minimum-evidence requirements, or pending recalculation. Every automatic access calculation SHALL use only the contributing signals enabled for that purpose in the frozen project configuration. Organization/global entry rules SHALL use the eligible per-signal inputs rather than an aggregate containing excluded signals; this SHALL NOT alter the independent organization/global assessment. Known-answer failures SHALL support automatic suspension. Disagreement SHALL default to informing reviewers and SHALL require explicit project opt-in for any automatic access effect. Automatic restrictions SHALL be project-scoped and SHALL NOT impose platform-wide account bans. Authorized reviewers SHALL receive the reason and supporting evidence; authorized managers with `projects.manage` SHALL be able to reinstate selected project-local automatic rules without changing the underlying answers or fabricating a score adjustment. Reinstatement and recalculation SHALL have attributable, repeatable outcomes.

#### Scenario: Known-answer failures cross an enforced threshold
- **WHEN** enough evaluated checks establish failure under a project's configured automatic action
- **THEN** the worker is suspended from new work in that project with a reason inspectable by authorized organization reviewers

#### Scenario: Repeated disagreement uses the default action
- **WHEN** established worker agreement falls below its configured minimum agreement percentage without explicit automatic-suspension opt-in
- **THEN** authorized reviewers receive the concern, but disagreement does not affect automatic admission or suspension, including through a combined score

#### Scenario: A broader score includes reviewer-only disagreement
- **WHEN** a project's entry rule uses global evidence but treats disagreement as reviewer-only
- **THEN** it uses only the eligible global signal inputs for admission rather than the aggregate containing disagreement, without changing the global assessment

#### Scenario: Only reviewer-only evidence is missing or pending
- **WHEN** the worker satisfies the project's automatic rules using current access-relevant evidence but a reviewer-only signal lacks enough evidence or awaits recalculation
- **THEN** that signal remains labeled appropriately for reviewers without making eligible admission evidence insufficient, denying access, or causing a retry

#### Scenario: A reviewer reinstates a worker
- **WHEN** an actor with reinstatement authority acts on a project restriction
- **THEN** the action records its reason and effect without granting access in another project or changing historical task evidence

### Requirement: Reinstatement evaluates selected rules using subsequent evidence
An authorized reinstatement SHALL identify the project, worker, selected project-local automatic rule(s), actor, explanation, related prior decision, and effective cutoff. Each selected rule SHALL evaluate only eligible evidence with an original source-event time after its latest reinstatement cutoff, within its existing history window and using its existing minimum samples and threshold. Answer-derived evidence SHALL use the original answer submission time; later review, peer completion, key correction, or rebuilding SHALL NOT renew that time. Insufficient post-reinstatement evidence SHALL permit participation under that rule; sufficient new evidence SHALL be eligible to trigger it again. A selected combined rule SHALL require its eligible contributors' existing minima from that subsequent evidence. Historical reputation and reviewer metrics SHALL remain unchanged by reinstatement, and unselected automatic rules, explicit blocks, and independent organization/global entry requirements SHALL remain effective. Replaying the same reinstatement request SHALL retain the original cutoff. Recalculation and expiration SHALL preserve the cutoff; a deliberate later reinstatement MAY establish a new one. No separate recovery thresholds, recovery score, or blanket exemption duration SHALL be introduced.

Each reinstatement SHALL require a nonblank explanation, valid selected local automatic rules and related prior decision for the same project/worker, and a caller-supplied UUID request key validated before persistence. Retry identity SHALL be scoped to project, worker, and requesting actor. After rechecking current `projects.manage` authority and reference scope, an identical successful replay SHALL return its original record and cutoff before applying checks about the current restriction. It SHALL NOT append a record, move any latest selected-rule reference, advance calculation guards, or enqueue another refresh. Changed content under the same scoped request key SHALL conflict. Replaying an earlier reinstatement after a later one SHALL leave the later effective cutoffs and references unchanged. A deliberate new reinstatement SHALL use a fresh request key; identical concurrent requests SHALL commit one record and one set of effects. Record creation, selected-rule reference updates, invalidation, and required scheduling SHALL commit or roll back together under the shared coordination contract.

#### Scenario: Rebuilding old failures after reinstatement
- **WHEN** a worker has been reinstated for a known-answer failure rule and its old answers are regraded or rebuilt
- **THEN** historical reputation reflects those answers but they cannot satisfy the selected rule's post-reinstatement minimum or restore its old suspension

#### Scenario: New evidence reaches the existing failure threshold
- **WHEN** enough eligible post-reinstatement answers meet the selected rule's existing minimum and fail its configured threshold
- **THEN** the rule can suspend new work again with attributable evidence, without a new recovery policy

#### Scenario: Another rule still denies entry
- **WHEN** reinstatement clears one rule but another automatic rule, explicit block, or independent organization/global entry requirement still denies access
- **THEN** the remaining rule continues to deny entry and the reinstatement does not grant a general access override

#### Scenario: A reinstatement request is retried
- **WHEN** the same successful reinstatement request is replayed after additional answers arrive
- **THEN** it retains its original cutoff and effect rather than restarting the evidence period

#### Scenario: An older reinstatement is replayed after a newer one
- **WHEN** an authorized actor identically retries a noon reinstatement after a deliberate one-pm reinstatement for the same rule has committed
- **THEN** replay returns the noon record while the one-pm cutoff remains effective, without another record, guard change, or refresh request

#### Scenario: Reinstatement retry content changes
- **WHEN** an actor reuses a scoped reinstatement request key with different selected rules, explanation, or related decision
- **THEN** the request conflicts without partial history, reference, or calculation changes

#### Scenario: Identical reinstatement requests compete
- **WHEN** concurrent currently authorized requests use the same project/worker/actor request key and identical content
- **THEN** one reinstatement and its original server cutoff commit, both requests recover that result, and effects are not duplicated

#### Scenario: A reinstatement replay loses authority
- **WHEN** the actor's management capability or active membership is revoked before replay
- **THEN** replay fails closed without revealing the record or changing any effective cutoff

### Requirement: Assessments publish coherent completed results
Each scoped assessment SHALL publish its scores, contributing counts, evidence provenance, and freshness together from one coherent fixed snapshot of source evidence, evaluation cutoff, effective settings, and applicable reinstatement inputs. Project assessments SHALL retain any rule-specific post-reinstatement inputs with that same publication. Project assessments SHALL NOT cache organization/global admission outcomes that must be refreshed before those newer scoped assessments can be used. Automatic access reasons SHALL be derived from completed assessment inputs during admission, not maintained as separate suspension state.

Publication SHALL advance the completed snapshot by captured input order rather than job completion time, without regressing the published source frontier or evaluation cutoff. Ordinary new answers, newly terminal attempt outcomes, or a time-window refresh boundary reached after capture SHALL NOT invalidate an otherwise valid result; they SHALL request a follow-up calculation and retain pending-refresh metadata. Key/review corrections, return classifications or corrections, key disabling or re-enabling, changes to effective settings, or reinstatement SHALL invalidate affected prepared results. A result using superseded protection inputs or an older snapshot SHALL NOT replace the effective publication. Reinstatement SHALL remain separately attributable and serialized with publication/admission without rewriting evidence or historical scores.

#### Scenario: New answers arrive during calculation
- **WHEN** a calculation has captured its inputs and more ordinary answers arrive before it finishes
- **THEN** its valid result can publish if it advances the completed snapshot, retaining its original cutoff and pending refresh for the additional answers instead of repeatedly restarting

#### Scenario: A correction invalidates a prepared calculation
- **WHEN** a key/review correction, return classification or correction, key disabling or re-enabling, effective-setting change, or reinstatement supersedes inputs used by a prepared result
- **THEN** that result is discarded and preparation repeats under the new inputs without overwriting a newer publication or pausing admission using completed assessments

#### Scenario: A faulty key is repaired
- **WHEN** a completed recalculation removes the evidence supporting an automatic suspension
- **THEN** the next admission evaluation uses the repaired assessment and no longer derives that failure reason, while unrelated valid reasons and explicit blocks remain effective

#### Scenario: Publication fails partway through
- **WHEN** publishing a new assessment fails before commit
- **THEN** none of its updated metrics become effective; admission continues to evaluate the previous completed inputs, and readers can see that the assessment needs updating

### Requirement: New work evaluates the latest completed assessments
Each request for new project work SHALL evaluate the frozen project's automatic rules using the latest completed assessment inputs in each required project, organization, or global scope, together with applicable reinstatement and current ordinary authorization. It SHALL select only access-relevant signals and apply their existing minima, weights, and thresholds. A prior denial SHALL NOT be a lasting restriction independent of those inputs. Once a required organization/global assessment improves enough, a new request SHALL be able to qualify without a separate project refresh job or manual clearing of that earlier denial. Newly completed evidence establishing failure SHALL likewise affect subsequent issuance without waiting for a project-specific copy of the broader result.

Access evaluations SHALL retain their outcome, reasons, time, effective settings, assessment references/as-of cutoffs, and reinstatement provenance as scoped decision history. Retaining an earlier outcome SHALL NOT make it authoritative for a later new-work request. Replaying an already committed allocation SHALL retain the existing allocation retry contract instead of rechecking reputation for new issuance.

#### Scenario: A denied worker earns enough broader reputation
- **WHEN** Project B previously denied a worker for insufficient broader reputation, a new organization/global assessment now satisfies that requirement, and the worker requests new work in B
- **THEN** admission uses the improved completed assessment without a B-specific refresh or manual reinstatement, permits work if all other requirements are met, and retains the previous denial as history

#### Scenario: Broader reputation now fails an entry rule
- **WHEN** a previously qualifying worker's latest completed organization/global assessment fails the project's configured entry rule
- **THEN** a new work request is denied using that result even if the project's local assessment has not changed, without revoking issued work

### Requirement: Pending recalculation keeps completed assessment inputs usable
Pending recalculation, source corrections, and time-window expiry SHALL mark affected assessments as needing refresh without withdrawing their completed inputs from admission. Authorized reads and decision history SHALL expose each input's as-of cutoff and pending update rather than present an old calculation as fresh. Fetch and direct assignment SHALL evaluate the latest completed inputs from each required scope even if another required scope awaits refresh. A pending scope SHALL NOT prevent use of a newer completed assessment in another scope.

A previously allowed worker SHALL NOT receive a new restriction, a reputation-updating retry response, or a grace-period timeout solely because recalculation is incomplete. With unchanged completed inputs, effective rules, and reinstatement, the reputation outcome SHALL remain unchanged. A prior denial SHALL continue only while the rules evaluated against those inputs still deny access. Ordinary account, organization, audience, explicit-block, lease, and capacity rules SHALL remain effective. Changed outcomes from newly completed assessments SHALL affect only subsequent issuance and SHALL NOT invalidate already-issued work.

#### Scenario: A global assessment is awaiting repair
- **WHEN** a key correction marks a contributing global assessment stale but recalculation is delayed
- **THEN** reports show the pending update and admission uses its last completed inputs alongside the latest completed inputs in other required scopes, without a scoring pause

#### Scenario: Supporting evidence expires before local evidence
- **WHEN** a required organization/global assessment reaches its expiration boundary while local evidence remains current
- **THEN** refresh is requested and admission continues to use completed inputs without a temporary pause

#### Scenario: An existing suspension awaits recalculation
- **WHEN** the assessments behind a denial await recalculation and their completed inputs, applicable reinstatement, and effective rules remain unchanged
- **THEN** another request produces the same reputation outcome; the pending job alone neither lifts nor adds a restriction

#### Scenario: Global reputation improves while local refresh remains pending
- **WHEN** a previously denied worker's global assessment now satisfies the entry rule and the completed local inputs already permit participation but await refresh
- **THEN** a new request can qualify using those completed inputs without waiting for the local refresh

### Requirement: First access does not depend on a queued initial calculation
If any required initial assessment is missing, the ordinary admission request SHALL authorize preparation, detect committed allocation retries, and calculate the missing assessment from eligible evidence before entering the allocation transaction or taking its Project/User/task locks. Unprocessed history SHALL NOT be classified as absent or require a queued-job wait. Completed inputs awaiting refresh SHALL remain usable with their pending/as-of metadata.

Under allocation locks, the request SHALL recheck current authorization, project state/configuration, the request key, the latest completed assessments in all required scopes, and reinstatement. It SHALL use concurrently completed assessments when available; otherwise it SHALL validate and publish the needed prepared candidates under the fixed-snapshot guards before evaluating admission. If a guard changed and a required completed assessment is still missing, it SHALL release allocation locks before preparing again in the request. Evidence scans, peer comparisons, and full history calculations SHALL NOT run while allocation locks are held; bounded rule evaluation over completed assessment metrics SHALL be permitted. Insufficient local evidence SHALL permit participation while configured organization/global entry requirements remain effective. No queued warm-up lifecycle, qualification attempt, or reputation-updating retry outcome SHALL be introduced.

#### Scenario: Eligible prior history has not been assessed yet
- **WHEN** a worker requests their first task in a project and required eligible organization/global evidence exists but its initial assessment job has not run
- **THEN** admission prepares the missing assessments outside allocation locks, then revalidates and publishes or uses concurrent completed assessments before evaluating issuance without waiting for the queued job

### Requirement: Reputation operations fail closed within organization scope
Organization settings, keys, assessments, return-classification history and actions, access-decision history, reviewer information, and restriction management SHALL require explicit organization scope and operation-appropriate management or review authority. Organization management SHALL require an active authenticated account, active organization, active membership, and explicit capability grants. Foreign and nonexistent targets SHALL fail without distinguishable disclosure. Worker sessions SHALL require an account while retaining existing optional-membership audience routes. Platform-controlled global summaries SHALL NOT disclose other organizations' raw evidence or grant management access.

Operations SHALL reuse the existing organization-scoped capabilities through the following explicit mapping, without introducing reputation-specific capability names:

| Operation | Required authority |
| --- | --- |
| Read/manage organization reputation defaults and draft-project settings | `projects.manage` |
| Create, inspect, correct, disable, or re-enable known-answer keys and inspect their retained management history | `projects.manage` |
| Read scoped reputation reports, assessments, access-decision history, and supporting own-organization evidence, including relevant keys/history | `tasks.review` |
| Inspect, classify, or correct worker returns and their classification history | `tasks.review`, with the existing self-review prohibition |
| Reinstate a worker for selected project-local reputation rules | `projects.manage` |
| Read a bounded global summary | `tasks.review` plus the qualifying organization work relationship |

Every operation and replay SHALL recheck the actor's current active account, owning organization, active membership, and required grant. Key inspection under `projects.manage` SHALL be an explicit scoped management read rather than implicit general source-read authority. Management alone SHALL NOT grant reputation reports or supporting-answer access; those reads SHALL require `tasks.review`. Review authority alone SHALL NOT grant settings/key mutations or reinstatement. An actor MAY hold both grants. Mere project-read permission, organization membership, or authority to perform work SHALL NOT grant either operation class. Worker-route privacy, the ordinary scoring of authorized key authors/readers who also work, return self-review denial, and bounded global disclosure SHALL remain unchanged. Global calculation settings SHALL remain platform-controlled.

#### Scenario: A manager inspects a key without review authority
- **WHEN** an active organization member has `projects.manage` but lacks `tasks.review`
- **THEN** scoped settings/key management, key-history inspection, and project reinstatement are permitted, while reputation reports, supporting submitted answers, and general access-decision-history reads remain denied

#### Scenario: A reviewer investigates without management authority
- **WHEN** an active organization member has `tasks.review` but lacks `projects.manage`
- **THEN** authorized reports and supporting own-organization evidence, including relevant keys/history, are inspectable and another worker's return can be classified, while settings/key mutations and reinstatement remain denied

#### Scenario: Ordinary project or worker access grants no reputation authority
- **WHEN** an actor has project-read or work authority without the required management/review grants
- **THEN** neither route discloses protected reputation reports or keys nor permits management or classification actions, even when the actor belongs to the organization

#### Scenario: A reviewer supplies another organization's assessment
- **WHEN** an otherwise authorized reviewer substitutes a foreign organization, project, worker assessment, or key reference
- **THEN** the operation discloses and changes no unauthorized record

#### Scenario: Management authority is revoked
- **WHEN** a manager loses the required capability or active membership before a mutation commits
- **THEN** the mutation fails closed without partial changes

### Requirement: Global summary disclosure requires an organization work relationship
An authorized organization reviewer SHALL be able to read a worker's bounded global summary only when retained scoped evidence establishes that the worker requested work while ordinarily authorized for that organization or performed work for it. An authenticated new-work request denied by an explicit broader reputation requirement SHALL still establish that review relationship through its retained scoped decision history. Supplying an arbitrary User identity or having organization membership alone SHALL NOT authorize general global-reputation lookup. Summary reads SHALL recheck the reader's active account, active organization, active membership, `tasks.review`, and the worker's scoped work relationship; unauthorized or nonexistent targets SHALL fail without distinguishable disclosure.

The global summary SHALL expose only aggregate metrics and evidence states, contributing counts, selected contributors and effective calculation settings, supporting original observation dates, calculation cutoff, and pending-refresh status. It SHALL NOT expose contributing organizations' names, source record references, submitted answers, known-answer keys, review details, or return reasons/classification history from other organizations. Detailed provenance SHALL remain retained for reproducible calculation without becoming cross-organization disclosure. Reviewers MAY separately inspect their own organization's evidence under existing scoped permissions. Internal global input use for authorized admission SHALL NOT grant the requesting organization a general summary-read or management capability. This requirement SHALL add no worker-facing reputation breakdown or dispute workflow.

#### Scenario: A reviewer investigates a worker who requested work
- **WHEN** a worker's authorized work request is denied by the organization's project reputation rule and a currently authorized organization reviewer reads their global summary
- **THEN** the retained request relationship permits the bounded aggregate summary without exposing evidence or organization names from other sources

#### Scenario: A reviewer attempts arbitrary worker lookup
- **WHEN** an otherwise authorized reviewer supplies a worker identity without a qualifying scoped request or performed-work relationship
- **THEN** the operation reveals no global summary or distinguishable information about whether that worker exists

#### Scenario: A global metric includes another organization's work
- **WHEN** an authorized reviewer inspects a global metric derived partly from another organization's submissions and review decisions
- **THEN** only aggregate metrics, counts, settings, observation dates, and freshness are disclosed, with no other organization names or source evidence

### Requirement: Recalculation is reproducible and safe to repeat
Assessments SHALL be rebuildable from retained authoritative evidence and the applicable scoped configuration. Equivalent evidence and calculation inputs SHALL yield equivalent assessments. Repeated calculation, submission retries, key corrections, and review retries SHALL NOT double-count evidence or duplicate restriction effects. Readers SHALL be able to distinguish a pending recalculation from an up-to-date calculation and identify the completed inputs used for each access evaluation. Repeated jobs SHALL preserve completed inputs until a replacement publishes; pending work SHALL NOT itself create or clear a restriction, and historical denials SHALL NOT override a fresh admission evaluation.

#### Scenario: A rebuild runs twice
- **WHEN** the same evidence and configuration are evaluated again
- **THEN** scores, counts, and effective restriction outcomes converge without duplicate penalties

#### Scenario: Admission needs an assessment under repair
- **WHEN** corrected evidence makes a required assessment stale before a worker fetches new work
- **THEN** allocation evaluates the latest completed assessment inputs with applicable reinstatement and ordinary authorization while the repaired result is calculated

### Requirement: Count windows select recent eligible observations per signal
For a count-only window with positive integer limit N, each signal SHALL independently select at most N eligible observations from the captured evidence snapshot. Selection SHALL first apply the declared scope, signal eligibility, source deduplication, evaluation cutoff, and any applicable reinstatement cutoff, then take the most recent observations by original source-event time. Equal event times SHALL use a stable source-observation identity as a deterministic tie-breaker, consistently across calculations and rebuilds. Correct and incorrect eligible known-answer evaluations SHALL both count; ineligible evidence and evidence for other signals SHALL NOT consume that signal's slots. If fewer than N observations qualify, the calculation SHALL use the actual available count and retain the existing minimum-evidence rules.

Answer-derived observations SHALL use original answer submission time; other signals SHALL use their defined original event time. Corrections SHALL update the same logical observation without adding a duplicate, changing its original event time, or changing its source-identity tie-breaker. An eligibility change SHALL rerun selection, allowing the next most recent eligible observation to fill an available slot. Count-only windows SHALL have no clock-driven expiration. Window selection SHALL preserve source history and SHALL NOT alter submission targets.

Initial project, organization, and global settings SHALL each default to N equal to one hundred under their explicit scoped-default contracts. Each signal SHALL use its own eligible observations rather than a shared pool of the worker's most recent answers; broader scopes SHALL apply the limit after pooling eligible source evidence. Fewer than one hundred observations SHALL use the available sample and its configured minimum, not require the worker to fill the window. Count-window scores SHALL persist through inactivity while their source evidence, configuration, and other calculation inputs remain unchanged; reports SHALL retain supporting observation dates rather than imply recent work from a newer calculation cutoff.

#### Scenario: New eligible evidence replaces an older observation
- **WHEN** a signal already has one hundred eligible observations under the initial project window and a new eligible observation with a later original source-event time is recorded
- **THEN** selection includes the new observation and excludes the oldest selected observation under the original-time and stable-identity ordering, while all authoritative source history remains retained

#### Scenario: An inactive worker retains a count-window score
- **WHEN** a worker with an established count-window signal supplies no new eligible evidence for several months and its other calculation inputs remain unchanged
- **THEN** inactivity alone does not expire the signal or change its score, and reports show the original oldest/newest supporting observation dates separately from the calculation cutoff

#### Scenario: Ordinary answers do not crowd out known-answer evidence
- **WHEN** a worker has more than twenty eligible graded known-answer responses interspersed with ordinary answers, skips, and disabled-key evaluations, with a count limit of twenty
- **THEN** the known-answer signal uses its twenty most recent eligible graded responses, including correct and incorrect answers, while other signals select their own evidence independently

#### Scenario: Reinstatement leaves fewer eligible observations than the window limit
- **WHEN** a selected local rule has five eligible observations after its reinstatement cutoff and a count limit of twenty
- **THEN** it uses those five without filling the remaining slots from pre-reinstatement evidence, applies its existing minimum, and leaves historical reputation unchanged

#### Scenario: Observations share a timestamp at the selection boundary
- **WHEN** more eligible observations share the boundary timestamp than fit in the remaining slots
- **THEN** the stable source-identity tie-breaker selects the same observations on equivalent rebuilds regardless of query or job completion order

#### Scenario: A correction changes an eligible answer's grade
- **WHEN** an answer is regraded and remains eligible
- **THEN** its corrected grade occupies the same original observation and ordering position rather than becoming a new recent observation or a second contribution

#### Scenario: A key is disabled for a selected observation
- **WHEN** disabling a key makes a selected known-answer observation ineligible
- **THEN** selection excludes it before applying the count limit and uses the next most recent eligible observation if available, without deleting the excluded source evidence

### Requirement: Time windows expire evidence without requiring a new submission
Each time-windowed assessment SHALL record its evaluation cutoff and next time-dependent invalidation, if any. Answer-derived observations SHALL be dated by the original answer's submission time; other time-windowed evidence SHALL use its signal's original event timestamp rather than job time. Key correction, delayed peer completion, and review correction SHALL NOT restart an observation's age. For duration W at cutoff T, eligible observations SHALL have original event times greater than T minus W and no later than T. The next invalidation SHALL be no later than the earliest included observation's original event time plus W. At or after that boundary, reads SHALL identify the calculation as needing refresh; scheduled recalculation and detection of a missed boundary SHALL request repair without requiring a new submission. Pending repair SHALL NOT pause allocation or make completed inputs unusable. Recalculation SHALL publish updated metrics with retained reinstatement cutoffs. Admission SHALL use those completed metrics to remove failure-based reasons whose threshold or minimum is no longer met, preserving other valid reasons, explicit blocks, and separate established organization/global entry requirements. If remaining local history falls below the minimum, the replacement SHALL report insufficient evidence and admission SHALL permit participation under that local rule, without fabricating a success score.

Initial project, organization, and global history SHALL remain count-based with one hundred eligible observations per signal. When time-based mode is selected without an otherwise configured duration under the existing scoped default/override resolution, its explicit initial duration SHALL be ninety days. Authorized organization settings and draft-project overrides SHALL be able to adjust that positive duration under the existing validation and activation-freezing contract; global settings SHALL remain independently platform-controlled. Time-based selection SHALL use all eligible observations whose original event times fall within the interval above, without applying the count-mode limit of one hundred. Each metric's ordinary evidence minimum SHALL apply to the resulting selected history. Excluded older source evidence SHALL remain retained. Count and time modes SHALL remain alternatives rather than simultaneous limits, and choosing time mode SHALL NOT create clock-driven expiration for unchanged count-mode assessments.

#### Scenario: Time mode starts at ninety days independently in each scope
- **WHEN** a project, organization, or global assessment selects time mode without an otherwise configured duration in its applicable scoped settings
- **THEN** that scope uses its explicit initial ninety-day duration under its own settings, without changing other scopes or the default mode of count-based assessments

#### Scenario: Time mode includes more than one hundred eligible answers
- **WHEN** an enabled known-answer metric has one hundred fifty eligible evaluated answers within its selected ninety-day interval
- **THEN** it uses all one hundred fifty answers and their underlying success/count rate, without truncating the sample to the count-mode limit of one hundred

#### Scenario: The ninety-day interval has precise boundaries
- **WHEN** a ninety-day time-windowed assessment evaluates at cutoff T
- **THEN** an observation at exactly T minus ninety days is excluded, one at T is included, and one after T is excluded, using original event times rather than correction or calculation times

#### Scenario: Older evidence leaves too little selected history
- **WHEN** enabled known-answer accuracy has nineteen eligible answers inside its selected ninety-day interval and one older answer outside it under the initial twenty-answer minimum
- **THEN** that metric reports insufficient evidence with nineteen selected answers rather than a success/failure percentage, while the older answer and source history remain retained

#### Scenario: A suspended worker produces no new answers
- **WHEN** the evidence supporting an automatic suspension expires out of the window
- **THEN** time-driven recalculation reevaluates it without requiring a new submission, and a fresh admission evaluation uses the completed result to remove the unsupported reason while retaining any other valid restriction

#### Scenario: The expiration job is delayed
- **WHEN** a worker requests work at or after the recorded invalidation time before the job runs
- **THEN** the missed refresh is detectable and repair is requested, while admission evaluates the latest completed inputs without a temporary pause

#### Scenario: A key correction concerns an old response
- **WHEN** correction occurs after that response's submission time has left the current window
- **THEN** history is repaired without making the old response recent or extending its enforcement lifetime
