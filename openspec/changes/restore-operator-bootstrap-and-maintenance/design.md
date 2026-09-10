## Context

Status: **future / deferred**, explicitly requested on 2026-09-09. Commit `ca7a7c4` is the last implementation before removal and is the reference for old behavior and tests, not a mandatory design to copy.

## Goals / Non-Goals

Restore useful operator setup and unattended maintenance once there is a concrete operational need. Prefer existing Ash actions and the selected libraries' current built-ins. Do not recreate generic manifests, duplicate creation actions, or maintenance-only fields before they are used.

## Decisions to revisit

1. Decide whether one operator command composes first-manager setup and explicit permission grants, and whether both steps must roll back together. Preserve exact active-user and organization scope, idempotency for identical inputs, no implicit reactivation or reassignment, and no wildcard authority. Share a consistent lock order across setup and granting. Keep capability ownership with the relevant domain.
2. Define session and OIDC retention intervals. Expiry, revocation, one-use OIDC claims, and inactive-account checks must remain independent of physical deletion. Preserve authentication event evidence and live credentials. Reintroduce scan indexes and retention metadata only where the chosen policy needs them.
3. Choose the storage provider before finalizing staging retirement. Handle live and expired finalizer claims, a publication completing after its caller times out, and a sealed object written before the database transition. Reverify and account for existing canonical content before cleanup completes. Retire upload identities only after descriptors and bounded in-flight writes expire or the provider fences writes; never delete canonical sealed content. Keep storage I/O outside database transactions. Add completion metadata and bounded, unique periodic scans only with the actual cleanup path.
4. Delete only expired open imports under the same lock used by append/finalize. Recheck eligibility, remove their rows and unreferenced candidate graphs transactionally through Ash, release batch identity only after successful deletion, and preserve all sealed provenance and revision references. Use restrictive database references as an independent guard.
5. Recheck the chosen Oban version for a durable terminal callback. If absent, use one bounded, unique reconciler for exact import-row workers and immutable row IDs. Lock/recheck pending rows before recording sanitized failure; race safely with late worker commits. Exclude jobs for already-terminal rows from pagination so they cannot starve recovery; continue draining full pages. Keep terminal job evidence until recovery is complete, with capacity and pruning limits evaluated together. Avoid custom per-attempt leases, counters, or a general job scanner. Initial row jobs are bulk-inserted once under the import sealing lock; the worker has no Oban uniqueness configuration. Any future path that creates replacement jobs must explicitly define its own concurrent duplicate-prevention boundary instead of assuming `Oban.insert_all` deduplicates jobs. Prefer retrying an existing job when that satisfies the chosen recovery contract.

## Current limitations while deferred

There is no operator bootstrap or manager grant convenience action. Primitive organization, membership, role, and capability actions remain, with test-only fixture composition. Expired session/OIDC records, staging objects, in-memory adapter access tokens, and abandoned imports accumulate. Abandoned imports retain their idempotency keys. Cancelled or exhausted import jobs can leave rows and batch progress pending; ordinary Oban pruning may later remove job evidence. Expiry checks and normal finalization/processing still work. This state is suitable for current development, not unattended persistent operation.

## Migration Plan

Review the removal migration and current database before restoring columns or indexes. Backfill retention/recovery facts deliberately; do not infer deleted maintenance timestamps or rely on pruned jobs. Decide how to handle accumulated staging, old imports, and pending rows without deleting immutable content. Revalidate the specifications before implementation.

## Verification

Restore meaningful lifecycle, authorization, concurrency, and provider-contract tests for the selected design. Exercise rollback, concurrent identical bootstrap, inactive conflicts, live-state retention, publication/cleanup races, late uploads, sealed-history preservation, terminal-job backlog draining, and recovery-versus-pruning. Run the repository verification gate and independent OpenSpec validation.
