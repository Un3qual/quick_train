## Why

The unreleased collection feature combines adaptive grouping, question-level fulfillment, a broad evidence API, and partitioned historical exports. The user approved simplifying all six architectural cost centers and confirmed there is no existing data or published API to preserve.

## What Changes

- Use one explicit ordered group model and one project-wide submission target applied to every task. Every attempt answers the full published form. Reviews classify answers without changing allocation demand.
- Remove balanced combination search, item coverage, question reservations/progress, failure escalation, and linked follow-ups. Count submitted and live attempts using native Ash aggregates while holding the task lock.
- Center public reads on tasks, submitted outcomes, work bundles, and receipts. Keep canonical Forms/Datasets resources and scoped nested traversal; remove per-child audit/accepted roots and standalone collection-definition roots.
- Export complete project results in accepted or audit mode. Pin each selected submitted outcome and its effective review decision once, deriving immutable related records from those owners. Remove arbitrary record-kind and UUID-range partitioning.
- Expose native Ash create/update project mutations, native child configuration upsert/destroy actions, native work-bundle reads, and native attempt transitions including submission. Centralize scoped locked reads and pending-asset staging setup through domain interfaces. Remove duplicate task identity data, bulk-expire overdue leases, and check cohort coverage through Ash queries. Unsealed export snapshots may retry after transient failures. Pin source identities at creation; drafts configure their cohort, bindings, slot policies, and project-level submission/skip settings.
- Regenerate the branch migration from the main baseline and remove intermediate snapshots and historical-response compatibility.

## Capabilities

### New Capabilities

### Modified Capabilities

- `projects`: A fixed source contract, explicit groups, and project-level collection settings.
- `task-allocation`: Whole-form attempts fulfill a task submission target independently of review.
- `task-responses`: Attempts own all form outcomes; project settings govern skips.
- `task-review`: Review history classifies submitted answers without driving allocation.
- `task-results`: Curated read roots and complete project exports with one membership per outcome.

## Impact

This deliberately changes unreleased GraphQL and domain APIs and removes unused scheduling resources. Authorization, exact immutable source/answer values, lease enforcement, atomic writes, review history, and reproducible verified export publication remain required. No new dependency, service, or framework is introduced.
