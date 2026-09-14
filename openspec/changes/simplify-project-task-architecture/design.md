## Context

See proposal.md. This is an approved simplification of the existing branch, preserving collection behavior and durable evidence.

## Goals / Non-Goals

**Goals:** Remove redundant persistence and dependency cycles while preserving concurrent issuance, immutable submitted answers, result-only context access, and repeatable exports.

**Non-Goals:** Change audience rules, answer targets, review history, selection fairness, or storage publication; introduce a scheduler, authorization grant ledger, or copied product data.

## Decisions

1. Attempt owns the draft revision and outcomes. Move existing revisions to attempts and redirect outcome foreign keys. Preserve historical response IDs only as private provenance metadata for reproducing previously sealed JSONL; new outcomes use their attempt identity. Remove the independently persisted Response lifecycle and its public query roots. Keep the save/submit operation names, returning Attempt.
2. Keep transactional progress counters and reconciliation. Derive attention from accepted/target/failure values and Task state from those rows and project closure through Ash calculations. This avoids another independently maintained projection layer.
3. The export records immutable form-context eligibility at snapshot seal. The pinned form version and immutable request filters determine presentation/question/option/label membership. Existing evidence and source-value membership remains relational; no timestamp cutoff replaces committed membership.
4. Activation initializes coverage for the frozen cohort. Balanced selection retains its existing coverage lock order. Explicit selection locks its next authored group and only that group's coverage rows; contention cannot reorder authored groups. Issuance still commits group consumption, inputs, reservations, and attempts together.
5. Collection context is a Tasks read boundary over the canonical immutable Forms/Datasets data. Foundational resources retain ordinary domain authorization. Read-only Ash resources share explicitly selected canonical attribute types/constraints, point to the existing tables with migration ownership disabled, and expose collection-only GraphQL types. Result input bindings use the same read boundary. The read boundary must expose only allowed context fields/relationships, enforce live worker or result authority on every traversal, and keep collections paginated. It must not add persisted copies or an authorization-state synchronization mechanism.

## Risks / Trade-offs

- Existing response IDs and export retries -> migrate provenance and retain the original JSONL field meanings without retaining a second lifecycle.
- Calculated state and access filters -> exercise direct Ash reads, GraphQL, completion, and correction races.
- Explicit group ordering and shared inputs -> retain stable locks and test independent-connection allocation.
- Context access could widen while removing foundation callbacks -> verify result-only and worker access, revocation, cross-project references, and reverse traversal.

## Migration Plan

Generate migrations with Ash codegen, then add the data transfer needed before removing redundant fields/tables. Retain historical migrations. Test with existing evidence in a disposable database and run the complete repository gate. JSON serialization must order keys explicitly: atom-map enumeration was runtime-dependent. Preserve published assets unchanged; detach only unpublished pending publication identities so they can regenerate the same sealed records with deterministic bytes. Retain the superseded assets' export ownership and normal staging expiry. Production rollback retains evidence and uses a forward fix; destructive down migrations remain a disposable-database operation.
