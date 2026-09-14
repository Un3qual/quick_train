## Why

The collection architecture stores a second response lifecycle for each attempt, maintains derivable status fields, snapshots already immutable form membership, and couples explicit issuance to balanced selection. Collection authorization needs an explicit integration with the existing domain resources, without duplicating their schemas. The user approved fixing all five findings from the branch architecture review.

## What Changes

- Make Attempt own draft revisions, submitted answers, and submission state; remove the Response resource and response-specific query roots.
- Calculate question attention and task status from transactional progress counters and project state.
- Pin immutable form context once per export, retaining committed membership for changing evidence and deterministic JSONL serialization across runtime restarts.
- Initialize coverage at activation and separate explicit group locking from balanced selection.
- Keep collection entry points in Tasks, reuse canonical domain resources, and centralize cross-domain collection/source checks in Authorization through native Ash policies and a scoped-read fragment.
- Preserve collected evidence, historical export provenance, leases, pagination, and organization boundaries.

## Capabilities

### New Capabilities

### Modified Capabilities

- `task-responses`: Attempt owns draft revisions and question outcomes.
- `task-review`: Attention and task state are derived projections.
- `projects`: Activation initializes frozen cohort coverage.
- `task-allocation`: Explicit issuance has a narrow locking boundary.
- `task-results`: Immutable form context uses a version-level snapshot and collection-owned reads.

## Impact

Projects/Tasks resources, GraphQL result shapes, authorization integration, migrations, and collection tests change. No dependencies or new external services are required.
