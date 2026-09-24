## Why

The repository still repeats capability predicates, dispatches manually across Ash subject types, and builds intermediate collections that its callers do not need. Simplifying those paths reduces maintenance work while preserving the current backend contract.

## What Changes

- Share the native Ash expression for active account, organization membership, and role capability checks across direct authorization and nested reads.
- Use Ash.Subject for organization argument/attribute lookup and Ash string constraints for trimming.
- Search structured errors directly with Enum.any? instead of constructing and flattening a path-keyed presentation tree.
- Stream pending import identifiers into transactional job batches and simplify the import admission branches.
- Resolve task-bound values through their Ash relationship filter instead of loading a revision just to retrieve its root-record ID.
- Record the reviewed architectural boundaries that still justify custom code.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is an internal refactor; `skip_specs: true` preserves the canonical contracts.

## Impact

Authorization checks, account/organization normalization, structured error classification, and import finalization. No API, schema, dependency, or backend-template boundary changes. Non-goals include redesigning storage publication, changing fingerprints, replacing batched dataset writes with per-record operations, or removing planned GraphQL/telemetry definitions.
