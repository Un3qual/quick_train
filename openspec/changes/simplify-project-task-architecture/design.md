## Context

See proposal.md. The feature is unreleased and has no existing data. Earlier branch schemas, IDs, API shapes, and generated export bytes do not need compatibility.

## Goals / Non-Goals

**Goals:** Make a task an explicit group of immutable inputs with a single submission target; make reviews and exports consumers of submitted answers; expose application workflows instead of every persistence detail.

**Non-Goals:** Change account/organization boundaries, weaken source authorization, remove answer families, or add scheduling infrastructure.

## Decisions

1. Keep explicit groups and create Task/TaskInput only on first issuance. Remove balanced grouping and coverage tracking. Authored order and optional per-attempt shuffling remain. Draft groups must be nonempty, distinct, and match slot policies; every enrolled item must occur in a group. Validate each group while streaming and use an Ash existence query for uncovered items; canonical-group uniqueness belongs to ExplicitGroup. Task identity is its unique explicit_group_id, without a second hash or encoded membership.
2. Each task takes its submission target from its frozen Project. Native counts of submitted attempts and physical live attempts determine remaining capacity under the Task lock. Bulk-expire overdue attempts with one atomic Ash update after acquiring the lock. Every attempt covers every published question. A valid submission counts once even when allowed questions are skipped. Reviews never reopen capacity. Remove per-question policies, offered-question rows, progress projections, failure escalation, reconciliation, and linked follow-ups.
3. Keep immutable per-question answers and append-only per-question review decisions. Automatic review accepts answered outcomes; manual review leaves them pending. Skips remain explicit and non-reviewable. Corrections change accepted results only. Keep task/attempt locks, optimistic draft revisions, idempotent submit/review requests, and exact published answer validation.
4. Expose tasks and submitted question outcomes through scoped paginated roots. An accepted-only outcome filter does not impose a separate visibility mode on each nested resource. Worker access remains through an owned live work bundle; terminal receipts expose state, timestamps, and review-status totals only. Reuse canonical Forms/Datasets/Assets resources and current collection filters; remove standalone collection-definition actions and roots.
5. Export the complete project in accepted or audit mode. A repeatable-read transaction seals one ExportSelection per eligible submitted QuestionResponse with the effective decision ID. All immutable children, task/input/attempt metadata, form context, bindings, and source values are derived from those selected owners. Audit history is bounded by the sealed decision number. No timestamp-only snapshot or later effective decision lookup substitutes for sealed membership. Output is deterministic and remains streamed to verified immutable assets. Remove evidence-kind and ID-range filters and historical response IDs. A failed transaction that has not sealed a snapshot may retry selection after checking current requester authority; a sealed snapshot is always reused.
6. Expose native Ash project create/update, child configuration upsert/destroy, and attempt start/release/cancel/submit mutations and domain interfaces. Keep attempt ownership, manager authority, and post-lock lease validation inside the native transition actions. Dataset/schema/form identities are fixed at creation, avoiding draft repinning. Binding, slot-policy, and worker-access resources own their native actions and return the affected child; destroys use scoped manager-authorized reads and record-based domain interfaces. Keep explicit child editing operations under the Project lock and revalidate the complete draft on activation. Project-level submission_target, skip_allowed, and reason_required replace per-question settings.
7. Expose work bundles directly through the native read action, ensuring its authorization fields are selected. Reuse scoped domain getters with explicit lock options and one internal export getter. Asset create_pending owns staging identity and expiry setup; registration builds that changeset before requesting storage access and persists it only after access succeeds.
8. Delete only branch-added migrations/snapshots, then generate the final schema from the main baseline with Ash codegen. Test on a new disposable database. No data-transfer or backward-compatibility paths are retained.

## Risks / Trade-offs

- Explicit groups require authored inputs; automatic grouping is intentionally removed.
- A rejected answer does not automatically request replacement work. Managers can create another project when additional collection is needed.
- Narrowed APIs change GraphQL shapes and root names; update repository callers and contract tests together.
- Derived counts must be read under a task lock after overdue attempts are terminalized to prevent over-allocation.
- Export retries must derive only immutable children and sealed review history; exercise concurrent submissions/corrections and restart reproducibility.

## Migration Plan

Generate a clean branch migration from main, retaining main migrations. Use a fresh dedicated test database and run the full verification gate. Development databases using an earlier branch schema must be recreated.
