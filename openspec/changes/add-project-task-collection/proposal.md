## Why

Before this change, QuickTrain could publish reusable forms and immutable dataset revisions but could not turn them into work or collect attributable answers. This change promotes the Projects and Tasks decisions in `record-future-product-architecture` into an executable contract for configuring projects, issuing work, collecting typed responses, reviewing outcomes, and exporting evidence.

## What Changes

- Add `QuickTrain.Projects`: one organization, dataset schema, explicit revision cohort, published form version, typed bindings, and frozen collection policy per project. Later enrollment uses a new project.
- Make PostgreSQL generate persisted record UUIDs and internal operation UUIDs across existing foundations and new collection resources. Use database defaults and returned records; keep caller-supplied retry tokens separate from database-generated record IDs. The project uses its UUID and editable title without a separate textual key, key-length settings, or custom hashing.
- Add `QuickTrain.Tasks`: fetch-time balanced or explicit selection, pool claims and direct assignments, leased attempts, recorded input presentation, and narrowly authorized worker access.
- Support organization members, external authenticated users, or both through a project-worker eligibility path. Keep one global User and keep organization-management authorization unchanged.
- Collect one mutable draft response per attempt, then atomically freeze explicit answered or skipped question outcomes. Persist scalar, non-image choice, ranking, and text-span answers relationally.
- Complete collection independently of detailed media support. Reject image-dependent forms with `unsupported_task_contract`; retain opaque-download inputs and keep existing published image-form definitions intact. Move image presentation, image choice, bounding boxes, polygons, raster masks, and mask uploads to [add-project-task-media](../add-project-task-media/proposal.md), which follows the separate verified-media change.
- Add append-only per-question automatic/manual review, linked follow-up attempts to a manager-selected eligible worker, bounded escalation, and rebuildable task progress and item coverage. Follow-up managers require both assignment and result-read permission and select predecessors through existing audit results.
- Expose deliberate GraphQL actions, bounded result inspection, and asynchronous immutable accepted-answer and audit exports, including pinned form presentation, question renderers and typed constraints, all child/history/context evidence, and optional type/ID ranges for selecting part of a task.
- Extend Forms, Datasets, and Assets with explicit attempt-owned and result-scoped access to referenced immutable definitions and bound source content, without granting general browsing or authoring rights.

MVP sizing policy: defer new application-level count and byte limits until actual usage informs them. This proposal adds no cohort/group, batch, answer/reason/explanation, annotation, or export-volume ceilings. Existing foundation request/upload behavior, published form constraints, paging, authorization, and data-integrity rules remain in force.

Explicit non-goals:

- Finance, prices, work offers, funding reservations, earnings, payouts, reputation, qualification/geography rules, or paid-work claims. Collection is uncompensated in this change.
- Adaptive/Elo/king-of-the-hill strategies, precomputed random pairings, consensus, canonical answers, adjudication, or synthesized final results.
- Editing active configuration, enrollment batches or configuration-version machinery, nested dataset records, JSONB answer/configuration content, or customer-specific tables.
- External forms, a frontend, image-dependent task execution, spatial response resources or mask uploads, audio/video range annotations, image decoding/rendering, or selecting and implementing an HTTP storage adapter.

## Capabilities

### New Capabilities

- `database-identities`: PostgreSQL-generated backend UUIDs, returned-ID relationships and form copying, database-issued asset/finalizer identities, and separate caller-supplied retry tokens.
- `projects`: frozen project cohorts, compatible bindings, collection policy, lifecycle, and organization management.
- `task-allocation`: audience eligibility, fetch-time selection, coverage, direct assignment, leases, and attempt-owned presentation.
- `task-responses`: atomic drafts/submission, explicit skips, scalar/choice/ranking answers, text spans, and source provenance.
- `task-review`: append-only question decisions, review concurrency, progress, escalation, and deliberate follow-up work.
- `task-results`: scoped paginated evidence and immutable asynchronous exports with a reproducible snapshot.

### Modified Capabilities

- `versioned-forms`: allow attempt-owned contract inspection and result-scoped inspection of the pinned published presentation and referenced question/option/label definitions through Tasks, preserving management policy and published identities.
- `datasets`: allow attempt owners and authorized result readers to inspect only the exact bound values and bindings from relevant issued immutable revisions through Tasks.
- `assets`: allow attempt-scoped and result-scoped opaque source downloads plus result-export downloads without general asset-management rights or weakening opaque-file delivery. Preserve ordinary registration's validation-before-persistence failure behavior and define failed access to an already-committed task-owned Asset without deleting or replacing that record.

## Impact

- Adds product domains above the existing Accounts, Organizations, Authorization, Assets, Datasets, and Forms foundations; those foundations remain reusable and the application remains backend-only. This is an intentional product extension, not a new generic service layer.
- Adds Ash resources, generated PostgreSQL migrations and snapshots, named transactional workflows, GraphQL allowlisted actions, and responsibility-specific Oban workers using the existing dependencies. No spatial resources, media service hooks, or deferred implementation checkboxes are required in this change.
- Depends only on the already archived authentication, datasets/assets, and versioned-forms capabilities. It can be implemented, verified, and archived before `add-project-task-media`, detailed media support, or a production HTTP storage adapter. Adapter contract tests cover opaque downloads and export publication; a compliant reachable adapter remains a deployment requirement for actual file transfer, not a completion gate for this change. Finance and Reputation remain independent.
- Aligns existing Ash UUID declarations and creation paths, including form graph copying and Assets staging/finalizer claims, with PostgreSQL generation while preserving all existing IDs. This is a generation-policy update within the existing resources, with no new domain, UUID service, registry, or dependency.
- Requires focused database identity, authorization, lifecycle, typed-value, selection-invariant, concurrency, export, and GraphQL checks, followed by `mise run openspec.validate` and `mise run verify` during implementation.
- Keeps the source architecture record as historical context and links it to this dedicated change. The implementation adds core collection; image execution remains in the separate media change.
