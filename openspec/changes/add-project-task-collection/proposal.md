## Why

QuickTrain can publish reusable forms and immutable dataset revisions, but organizations cannot yet turn them into work or collect attributable answers. This change promotes the Projects and Tasks decisions in `record-future-product-architecture` into an executable contract for configuring projects, issuing work, collecting typed responses, reviewing outcomes, and exporting evidence.

## What Changes

- Add `QuickTrain.Projects`: one organization, dataset schema, explicit revision cohort, published form version, typed bindings, and frozen collection policy per project. Later enrollment uses a new project.
- Add `QuickTrain.Tasks`: fetch-time balanced or explicit selection, pool claims and direct assignments, leased attempts, recorded input presentation, and narrowly authorized worker access.
- Support organization members, external authenticated users, or both through a project-worker eligibility path. Keep one global User and keep organization-management authorization unchanged.
- Collect one mutable draft response per attempt, then atomically freeze explicit answered or skipped question outcomes. Persist scalar, choice, ranking, bounding-box, polygon, raster-mask, and text-span answers relationally.
- Preserve the separately scoped media prerequisite: image execution requires verified source facts and serving support from that change. This change defines the annotation integration and rejects unsupported image projects until that prerequisite is present; it does not add decoders, previews, or a storage provider.
- Add append-only per-question automatic/manual review, linked follow-up attempts, bounded escalation, and rebuildable task progress and item coverage.
- Expose deliberate GraphQL actions, bounded result inspection, and asynchronous immutable accepted-answer and audit exports.
- Extend Forms, Datasets, and Assets with explicit attempt-owned access without granting general browsing or authoring rights to workers.

Explicit non-goals:

- Finance, prices, work offers, funding reservations, earnings, payouts, reputation, qualification/geography rules, or paid-work claims. Collection is uncompensated in this change.
- Adaptive/Elo/king-of-the-hill strategies, precomputed random pairings, consensus, canonical answers, adjudication, or synthesized final results.
- Editing active configuration, enrollment batches or configuration-version machinery, nested dataset records, JSONB answer/configuration content, or customer-specific tables.
- External forms, a frontend, audio/video range annotations, image decoding/rendering, or selecting and implementing an HTTP storage adapter.

## Capabilities

### New Capabilities

- `projects`: frozen project cohorts, compatible bindings, collection policy, lifecycle, and organization management.
- `task-allocation`: audience eligibility, fetch-time selection, coverage, direct assignment, leases, and attempt-owned presentation.
- `task-responses`: atomic drafts/submission, explicit skips, typed answers, annotations, and source provenance.
- `task-review`: append-only question decisions, review concurrency, progress, escalation, and deliberate follow-up work.
- `task-results`: scoped paginated evidence and immutable asynchronous exports with a reproducible snapshot.

### Modified Capabilities

- `versioned-forms`: allow an authorized attempt owner to inspect only its pinned published contract through Tasks, preserving management policy and published identities.
- `datasets`: allow an authorized attempt owner to read only bound values from its allocated immutable revisions through Tasks.
- `assets`: allow attempt-scoped source downloads and response-mask uploads, plus result-export downloads, without general asset-management rights or weakening opaque-file delivery.

## Impact

- Adds product domains above the existing Accounts, Organizations, Authorization, Assets, Datasets, and Forms foundations; those foundations remain reusable and the application remains backend-only. This is an intentional product extension, not a new generic service layer.
- Adds Ash resources, generated PostgreSQL migrations and snapshots, named transactional workflows, GraphQL allowlisted actions, and responsibility-specific Oban workers. Existing dependencies should suffice for collection; media dependencies belong to the separate prerequisite.
- Depends on the already archived authentication, datasets/assets, and versioned-forms capabilities. Image execution and deployment with reachable asset/export URLs additionally depend on the separate media/storage work recorded in the source architecture. Planning and non-image collection do not depend on Finance or Reputation.
- Requires focused authorization, lifecycle, typed-value, selection-invariant, concurrency, export, and GraphQL checks, followed by `mise run openspec.validate` and `mise run verify` during implementation.
- Keeps the source architecture record as historical context and links it to this dedicated change. No runtime changes are made by this proposal.
