## Status

**Future / deferred. Do not implement automatically.** Resume only after an explicit decision to prioritize operator onboarding and operational readiness, once organization workflows and the storage provider are better understood.

## Why

Operator setup and background maintenance were removed during early dataset/asset development to reduce code that is not yet needed. Restore these capabilities before relying on unattended operation with persistent data.

## What Changes

- Restore operator-only organization manager setup and explicit dataset/asset capability grants, using ordinary Ash actions where possible.
- Restore bounded authentication retention, staging cleanup, expired-open-import cleanup, and recovery of pending rows whose Oban jobs are cancelled or discarded.
- Revalidate storage guarantees, retention intervals, schedules, schema metadata, and concurrency tests against the implementation at that time.

## Capabilities

### New Capabilities
- `operational-maintenance`: Deferred operator setup, retention, staging/import cleanup, and terminal-job recovery.

### Modified Capabilities
None in this deferred proposal. On resumption, reconcile the authentication, asset, and import specs with these restored guarantees.

## Impact

Affects Accounts, Organizations, Authorization, Assets, Datasets, storage adapters, Oban configuration, schema migrations, and operator documentation. No runtime code is added by this proposal. The current removal is tracked in section 14 of `add-normalized-datasets-and-assets/tasks.md`.

Non-goals: automatic implementation now, a generic bootstrap/recovery framework, wildcard grants, frontend onboarding, or restoring old code unchanged merely because it existed.
