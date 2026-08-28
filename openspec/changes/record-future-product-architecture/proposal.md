## Why

QuickTrain has approved cross-domain decisions for Forms, Projects, Tasks, Finance, and Reputation that must remain durable without expanding the first dataset/assets release. This documentation-only change preserves those decisions until each product domain receives its own scoped OpenSpec change.

## What Changes

- Record the approved product-domain boundaries, dependency direction, and named cross-domain workflows.
- Preserve approved decisions for versioned forms, dataset bindings, project cohorts, fetch-time task selection, worker audiences, attempts, responses, skips, reviews, exports, advanced annotations, finance, and reputation.
- Mark every recorded decision as deferred architecture rather than a current behavioral requirement or implementation task.
- Require each future product change to restate and validate the relevant decisions in its own proposal, specs, design, and tasks before implementation.

Explicit non-goals:

- Adding or modifying runtime capabilities, database tables, GraphQL fields, jobs, dependencies, or implementation tasks.
- Making this record a prerequisite for `add-api-authentication` or `add-normalized-datasets-and-assets`.
- Preventing a later explicit product decision from revising the recorded architecture.

## Capabilities

### New Capabilities

None. This change is documentation-only and declares `skip_specs: true`.

### Modified Capabilities

None.

## Impact

- Adds only OpenSpec planning artifacts.
- Removes future-product architecture from the implementation-focused dataset/assets design while keeping the approved decisions discoverable in the same durable planning system.
- Leaves the reusable backend template and runtime behavior unchanged.
