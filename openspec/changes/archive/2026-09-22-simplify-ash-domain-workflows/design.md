## Context

The user approved all thirteen audit findings at baseline `93cbe41`. See proposal.md. Existing transaction order, immutable content, scoped authorization, error precedence, and retry behavior remain binding.

## Goals / Non-Goals

**Goals:** Resource actions own persistence and policies, domain interfaces own invocation, and each workflow loads only the data it consumes.

**Non-Goals:** Generic orchestration frameworks, caches, stored projection counters, persistence redesign, or restoration of deferred functionality.

## Decisions

1. Bound discovery and JWKS HTTP calls through oidcc request options below the metadata cache's total caller deadline. Translate expected cache timeout/unavailability exits to provider errors so login state is discarded. Keep endpoint validation and fail-closed metadata expiry.
2. Replace dataset schema draft/publication and record-type/field generic CRUD wrappers with native actions. Before-action changes preserve scoped parent locks, draft checks, and refreshed child data. Use native GraphQL mutation envelopes and update callers together.
3. Form copy becomes a native create using version allocation and transactional graph-copy hooks; publication becomes a native update using the version lock, graph validation, state/timestamp changes, and set_result for idempotent repeats. Keep graph copying/reordering and copy rollback semantics.
4. Import open becomes an action-declared upsert on organization/dataset/key with no overwrite fields. Changes derive requester/fingerprint/expiry; validate returned retry facts without changing existing lifetime or caller identity.
5. Reuse Accounts interfaces for session/identity reads/writes. Add a scoped locked import read and domain interfaces for existing internal import writes instead of duplicate call-site changesets. Preserve bypass only within trusted orchestration.
6. Complete projects with one atomic conditional state update using the existing single post-lock cutoff. Check unsupported form questions with an existence query while retaining required collections.
7. Attempt policies express active ownership and worker eligibility so generated permission checks agree with authorization. Keep owner, lease and lifecycle rechecks after locks; terminal receipt/retry semantics remain unchanged.
8. Consolidate common scalar validity and canonicalization in a small dataset boundary backed by native Ash types. Retain strict selector input admission, Decimal library bounds, import byte limits, structural rejection ordering, and persisted domain-failure semantics.
9. Separate published schema identity from field hydration. Incoming rows load required or supplied fields; stored candidates load the field definitions of their actual values. Do not add a schema cache or field ceiling.
10. Export recovery checks its owned pending asset before creating a file. Ready/duplicate-content assets supply persisted content facts for canonical verification/access/ready transition; pending/failed/expired assets retain generation/replacement behavior and immutable snapshot membership.
11. Load calculated Task state on public/domain presentation reads or explicit consumers. Internal lock/guard/allocation reads remain lean; preserve derived counts and state.
12. Submission prepares distinct text-span source data once, including lengths, with Ash relationship loading. Per-question checks retain binding, input/source provenance, schema/organization scope, and Unicode codepoint boundaries. Draft save remains scoped to its one answer.

## Risks / Trade-offs

- Native actions change unreleased GraphQL shapes and record-based domain signatures; update fixtures and API callers and run authorization/lifecycle tests together.
- Permission policies must preserve optional external-worker membership and idempotent terminal operations. A policy preflight never replaces post-lock checks.
- Filtered field loading must include required fields even when absent from input and retain unknown-field rejection.
- Export recovery must verify owned canonical bytes and never trust an unrelated asset or rerun snapshot selection.
- Parallel implementation uses disjoint file ownership and separate test databases; the coordinator owns shared fixtures, specs, integration verification, and commits.

## Migration Plan

No database migration is expected. Start with existing generated resources and use Ash generators for new change modules where practical. Update native callers in the same commits. Run focused behavior/concurrency tests, OpenSpec validation, and the full repository gate.

The approved closeout includes the minimum stable security patches: Ash 3.33.4 for `EEF-CVE-2026-86338` and Mint 1.10.1 for `EEF-CVE-2026-82672`. Update the exact Ash requirement and those two lock entries, retaining Mint as a transitive dependency and preserving unrelated packages and the existing mise toolchain. Run the full gate without audit exceptions before archiving this change and `simplify-project-task-architecture`.
