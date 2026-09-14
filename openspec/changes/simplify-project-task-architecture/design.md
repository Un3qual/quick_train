## Context

See proposal.md. This is an approved simplification of the existing branch, preserving collection behavior and durable evidence.

## Goals / Non-Goals

**Goals:** Remove redundant persistence and resource models while preserving concurrent issuance, immutable submitted answers, result-only context access, and repeatable exports.

**Non-Goals:** Change audience rules, answer targets, review history, selection fairness, or storage publication; introduce a scheduler, authorization grant ledger, or copied product data.

## Decisions

1. Attempt owns the draft revision and outcomes. Move existing revisions to attempts and redirect outcome foreign keys. Preserve historical response IDs only as private provenance metadata for reproducing previously sealed JSONL; new outcomes use their attempt identity. Remove the independently persisted Response lifecycle and its public query roots. Keep the save/submit operation names, returning Attempt.
2. Keep transactional progress counters and reconciliation. Derive attention from accepted/target/failure values and Task state from those rows and project closure through Ash calculations. This avoids another independently maintained projection layer.
3. The export records immutable form-context eligibility at snapshot seal. The pinned form version and immutable request filters determine presentation/question/option/label membership. Existing evidence and source-value membership remains relational; no timestamp cutoff replaces committed membership.
4. Activation initializes coverage for the frozen cohort. Balanced selection retains its existing coverage lock order. Explicit selection locks its next authored group and only that group's coverage rows; contention cannot reorder authored groups. Issuance still commits group consumption, inputs, reservations, and attempts together.
5. Collection entry points remain in Tasks, but reads reuse the canonical Forms, Datasets, Assets, and ProjectInputBinding resources and their GraphQL types. The Authorization layer owns the shared collection-access filter and organization/source authority checks. A native Ash DSL fragment adds the scoped definition read to existing form/field resources; each resource permits collection access explicitly alongside ordinary read policies. Do not duplicate schemas, relationships, field lists, ordering, or GraphQL types to move authorization. Native Asset field policies hide private storage/claim fields. Every collection traversal still requires current live-worker or result authority for the exact issued input and bound field, and collections retain their owning resource pagination.

## Risks / Trade-offs

- Canonical resources explicitly integrate with shared collection authorization. This modest policy coupling is preferable to a second model of the same entities; mutation logic and schemas remain solely in their owning domains.

- Existing response IDs and export retries -> migrate provenance and retain the original JSONL field meanings without retaining a second lifecycle.
- Calculated state and access filters -> exercise direct Ash reads, GraphQL, completion, and correction races.
- Explicit group ordering and shared inputs -> retain stable locks and test independent-connection allocation.
- Sharing canonical resource reads could widen collection access -> verify result-only and worker access, revocation, cross-project references, and reverse traversal.

## Migration Plan

Generate migrations with Ash codegen, then add the data transfer needed before removing redundant fields/tables. Retain historical migrations. Test with existing evidence in a disposable database and run the complete repository gate. JSON serialization must order keys explicitly: atom-map enumeration was runtime-dependent. Preserve published assets unchanged; detach only unpublished pending publication identities so they can regenerate the same sealed records with deterministic bytes. Retain the superseded assets' export ownership and normal staging expiry. Production rollback retains evidence and uses a forward fix; destructive down migrations remain a disposable-database operation.
