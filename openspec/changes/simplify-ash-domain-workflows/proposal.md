## Why

The approved thirteen-finding audit found duplicated Ash action ownership, inconsistent permission and scalar-validation boundaries, and repeated work in imports, submissions, and export recovery. Consolidating these responsibilities makes the existing backend behavior easier to maintain and cheaper to execute.

## What Changes

- **BREAKING**: Use native dataset schema/child authoring, import-open, form-copy, and form-publish actions and their generated domain and GraphQL mutation interfaces. Update repository consumers to native input/result/errors shapes.
- Bound OIDC provider metadata work and return failures through the existing login cleanup path.
- Reuse generated domain interfaces and declare attempt ownership/eligibility in policies as well as post-lock checks.
- Share strict scalar normalization; load only relevant dataset fields and submission sources.
- Resume already-published exports without regenerating bytes, narrow Task state loading to consumers, and use native existence/atomic operations for activation and completion.

Non-goals: new product features, changes to normalized persistence, relaxed authorization or locks, persistent caches, new workflow frameworks, deferred maintenance/media work, or dependency upgrades.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `api-authentication`: Metadata timeout failures use the normal sanitized error/cleanup path.
- `datasets`: Native authoring interfaces and consistent finite scalar validity with bounded field loading.
- `dataset-imports`: Native import opening with immutable retry facts.
- `versioned-forms`: Native copy and publication mutation contracts.
- `task-responses`: Accurate permission checks and submission-local source validation.
- `task-results`: Publication recovery reuses verified immutable bytes.

## Impact

Accounts/authentication, Datasets, Forms, Projects, Tasks and their GraphQL/domain callers and tests. No schema or dependency change is intended. The backend-only template and global User/optional membership model remain intact.
