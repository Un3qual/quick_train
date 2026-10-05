## 1. Finalize the Implementation Contract and Generate Resources

- [ ] 1.1 Resolve the design's explicitly listed pre-implementation decisions: scoring/defaults and cold-start admission, supported typed matching, organization/global evidence rules, capabilities and reviewer delivery, reinstatement semantics, and freshness/lock ordering. Record the concrete choices and reconcile proposal/design/spec scenarios before writing runtime code; do not treat the documentation approval as approval of unchosen numerical defaults.
- [ ] 1.2 Inspect installed generators with `mise exec -- mix help ash.gen.domain` and `mise exec -- mix help ash.gen.resource`; generate the Reputation domain and the minimum resources required for scoped settings, known-answer history, rebuildable assessments, and recoverable project restrictions. Apply native Ash UUIDs, domain interfaces, explicit organization references, and additive AshPostgres constraints/migrations without creating a generic policy or event framework.

## 2. Author Settings and Private Known-Answer Evidence

- [ ] 2.1 Implement capability-authorized organization defaults and draft-project overrides; validate bounded settings and freeze one coherent effective configuration at activation. Preserve existing active projects' admission behavior. Verify foreign scope, missing authority, invalid settings, defaults racing activation, and later default edits in focused Projects/Reputation tests.
- [ ] 2.2 Implement exact Task/question/input-scoped typed keys, authoring validation, and retained correction/disabling history with actor/reason and retry/concurrency semantics. Verify stable option/input identities, numeric tolerance boundaries, different revisions sharing one question, and explicit unsupported-family errors.
- [ ] 2.3 Expose manager-authorized key/settings actions through native Ash/GraphQL interfaces while excluding keys and check designation from worker bundles, nested traversal, errors, and mutation results. Verify both member and external-worker routes, cross-organization denial, and management without implicit general read access; run focused tests and commit this slice.

## 3. Calculate Explainable Scoped Assessments

- [ ] 3.1 Implement the finalized application-owned calculation for known-answer accuracy, effective substantive human review, reliability/experience, evidence counts/windows, and unknown/provisional history. Preserve source provenance, exclude automatic acceptance as correctness evidence, and keep skips from becoming automatic penalties. Verify meaningful boundaries and correction inputs with focused tests.
- [ ] 3.2 Implement peer comparison with exact task/question contracts, distinct peers, self/duplicate exclusion, stable identities, minimum peers and worker history, strong consensus, and robust numeric tolerance. Verify sparse/split/tied evidence, shuffled presentation, subjective-project disabling, and recalculation of earlier comparisons when new peers submit.
- [ ] 3.3 Build project/organization/global projections under the finalized scope rules; keep platform calculations independent of local weights and private organization evidence. Add bounded authorized assessment reads showing signal counts, provenance, and freshness. Verify isolation and reproducible rebuilding from the same evidence; run focused tests and commit assessment calculation.

## 4. Recalculate and Support Reviewer Recovery

- [ ] 4.1 Integrate submission, effective review correction, and key correction/disabling with transactional invalidation and responsibility-specific Oban recalculation. Verify retries, partial job failures, affected-peer expansion, and conditional publication so obsolete results cannot replace newer assessments. Preserve submitted evidence, task satisfaction, and sealed exports.
- [ ] 4.2 Implement reviewer information and attributable project/user restrictions with per-signal actions. Default disagreement to informing reviewers, require explicit project opt-in for suspension, and enforce minimum evidence. Surface widespread key failures for review without adding automatic project pausing.
- [ ] 4.3 Implement authorized reinstatement and repaired-evidence reevaluation using the finalized recovery semantics. Verify that replaying an action or rebuilding the same evidence does not duplicate effects or accidentally undo reinstatement, that new evidence follows the defined rules, and that source answers/scores are not manually fabricated; run focused tests and commit recovery workflows.

## 5. Enforce Admission Without Revoking Issued Work

- [ ] 5.1 Add the reputation gate to both fetch and direct assignment after durable retry resolution and before new issuance. Preserve existing ongoing account/audience/lease/ownership checks; do not reuse the revoking project block for reputation-only suspension. Refresh known-stale admission assessments or return a retryable outcome.
- [ ] 5.2 Verify suspended fetch/assignment denial, audience allow entries not bypassing suspension, unaffected other projects, completion of already-issued work, unchanged explicit-block revocation, and retry of a committed allocation after its response is lost and suspension occurs. Confirm unchanged submission capacity and review/results behavior.
- [ ] 5.3 Use independent database connections and barriers to verify restriction/reinstatement versus issuance, source correction versus assessment publication, and submission/review versus invalidation without lock inversions. Assert rollback leaves no partial attempt/presentation and old calculations cannot restore repaired restrictions; run focused integration tests and commit allocation enforcement.

## 6. Verify and Reconcile the Change

- [ ] 6.1 Verify additive migration up/down/reapply in a disposable database with existing users, active projects, attempts, review chains, and sealed exports. Confirm old active projects acquire no new restrictions and document a deployment rollback that retains new authoritative key/recovery evidence.
- [ ] 6.2 Reconcile the artifacts with implemented behavior and replace the pre-implementation decision list with the actual contract. Keep the compensation integration terms and competitor evidence in this change; expose only the needed reputation evidence, leaving Finance offers, funding, bonuses, and settlement to a separate change. No Finance implementation is required to complete reputation.
- [ ] 6.3 Run `mise run openspec.validate`, then `mise run verify`; inspect relevant logs and resolve failures. Commit and archive only after implementation tasks and verification pass. Planning validation alone does not complete these tasks.
