## 1. Narrow the collection API

- [x] 1.1 Replace per-resource audit/accepted roots with scoped task and outcome reads; retain secure nested traversal and worker bundles/receipts.
- [x] 1.2 Remove standalone collection definition roots/fragments and update API/security tests.

## 2. Simplify complete project exports

- [x] 2.1 Remove partition filters and pin one outcome/decision membership; derive immutable context and sealed review history.
- [x] 2.2 Remove historical response identity compatibility and verify exact output, isolation, and publication retries.

## 3. Simplify allocation and review coordination

- [x] 3.1 Keep explicit groups and one submission target per task; remove balanced selection, coverage, question reservations/progress, failure escalation, and follow-ups.
- [x] 3.2 Offer the whole form, keep project-level skip rules, and separate review decisions from allocation capacity.
- [x] 3.3 Verify concurrency, lease expiry, ownership, submission/review semantics, and explicit presentation ordering.

## 4. Simplify project authoring

- [x] 4.1 Expose native Ash mutations/interfaces and freeze source references at creation.
- [x] 4.2 Remove obsolete dispatch and question-policy editing; update callers and GraphQL assertions.

## 5. Consolidate and verify

- [x] 5.1 Synchronize canonical/delta/deferred specs and README with the simplified contract.
- [x] 5.2 Regenerate one final branch migration and snapshots from main; verify fresh database setup.
- [x] 5.3 Run mise run openspec.validate and mise run verify; review the final diff and commit the work.

## 6. Address architecture review findings

- [x] 6.1 Retry unsealed export snapshots after transient failures, with current authorization and a concurrent-rename regression test.
- [x] 6.2 Bulk-expire overdue attempts under existing owner locks and validate group coverage without retaining the whole cohort.
- [x] 6.3 Expose native attempt updates directly and remove redundant task group identity data.
- [x] 6.4 Regenerate the unreleased branch schema, update callers/specs, run the verification gate, and commit.

## 7. Use native actions and domain interfaces

- [x] 7.1 Remove the generic work-bundle bridge and preserve authorization under GraphQL field selection.
- [x] 7.2 Move binding, slot-policy, and worker-access mutations to native child-resource upsert/destroy actions under the Project lock.
- [x] 7.3 Make submission a native Attempt update with transactional validation and automatic decisions.
- [x] 7.4 Centralize scoped locked lookups and pending-asset setup behind domain interfaces.
- [x] 7.5 Update API callers and specifications, verify authorization/concurrency/retries, run the full gate, and commit.

## 8. Recover expired export staging

- [x] 8.1 Replace expired unpublished export assets under the export lock, preserve sealed content, add expiry retry coverage, synchronize specifications, and run the verification gate.

## 9. Address local CodeRabbit review findings

- [x] 9.1 Remove the policy for deleted review read actions and synchronize the Forms inspection specification with whole-form attempts; run the verification gate.
