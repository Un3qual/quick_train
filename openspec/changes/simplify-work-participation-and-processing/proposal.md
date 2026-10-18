## Why

Workers should receive a small, usable work unit in one step. Durable task reservations, review defaults and import processing can preserve correctness with fewer states, locks and background jobs.

## What Changes

- **BREAKING**: Name the existing worker-attempt entity TaskParticipation and use one active state plus submitted, returned, expired and cancelled outcomes. Keep allocation origin and start time as independent facts.
- Reserve one response slot per Task using a durable fixed deadline; enforce expiry in allocation and worker actions without an individual expiration job.
- Remove shared Task write locks from worker reads, start and draft saves; retain participation, Project and capacity protections where required.
- Derive automatic acceptance from submitted answers and frozen review mode. Store only explicit human review decisions, preserving attributable corrections and conflict checks. Include the frozen review mode once in export headers so absent decisions remain interpretable without synthetic review records.
- Process a sealed dataset import with one durable job that pages pending rows and reuses each row's atomic transaction.
- Remove the unused asset-verification worker. Retain result-export jobs and synchronous asset finalization.
- Explain Project, Task and Question boundaries to organizations, including submission targets and allowed skips. Keep ordinary small-Task validation/submission atomic without per-question jobs/checkpoints; retain bulk-history and API pagination safeguards.

Non-goals: runtime implementation during this planning pass, a payment system, per-question quotas, multiple-task prefetch, in-memory allocation authority, a lease service, generic batching infrastructure or production compatibility work.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `task-allocation`: task-level reservations, reduced participation lifecycle and narrower worker-read locking.
- `task-responses`: participation-owned drafts and saves without shared Task write locks.
- `task-review`: implicit automatic acceptance with explicit human decisions and predecessors.
- `task-results`: participation metadata and returned outcomes, narrower worker bound-value/source-download authorization guards, and interpretable frozen review defaults in sealed exports.
- `dataset-imports`: one processing job per sealed import with bounded, retry-safe row processing.
- `projects`: authoring guidance for independently completable Tasks and their Question bundles.

## Impact

This is a supporting collection change for [worker reputation](../add-worker-reputation/proposal.md); implement its native contracts before adding reputation hooks. Reputation owns reliability classifications, shared peer references and refresh scheduling. This change adds no reusable backend-template responsibility or external dependency: it changes QuickTrain's Tasks, Datasets and Assets product code and its scoped GraphQL/domain contracts using existing Ash and Oban facilities. QuickTrain is unreleased: update resource names, schema, fixtures and APIs directly, without legacy aliases or backfills.
