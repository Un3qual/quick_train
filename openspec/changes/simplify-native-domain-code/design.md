## Context

Whole-repository review at `aa23adc`, including Accounts, Authorization, EnterpriseIdentity, Datasets, Forms, Projects, Tasks, Assets, HTTP storage, and their boundary tests. Earlier simplification changes already moved most persistence and lifecycle operations into Ash. See proposal.md for this pass's scope.

## Goals / Non-Goals

Reduce repeated policy logic and unnecessary traversal while preserving organization scope, error categories, transactional scheduling, and existing APIs. No new framework, generic persistence layer, schema migration, or compatibility path is needed.

## Decisions

1. Keep a reusable Ash expression on RoleAssignment for active account/organization, active membership, and capability membership. Direct capability checks, source reads, and result reads apply their own explicit organization correlation around that expression. This removes three separately maintained copies without moving authorization into application-side joins or weakening worker-specific rules.
2. Dispatch organization lookups through Ash.Subject.get_argument_or_attribute/2 for supported subjects; retain a fail-closed fallback for absent/unsupported subjects. Ash's string type already trims input; custom changes only need the business-specific lowercase conversion.
3. Search nested error lists with Enum.any?/2. The existing conversion into a path-keyed presentation map and subsequent flattening is unnecessary for a predicate and can collide when one error path prefixes another. Preserve constraint metadata handling and structured category matching; never inspect error message text.
4. Use Ash.stream! with keyset pagination to read pending import IDs and Stream.chunk_every to enqueue bounded batches under the existing import lock and transaction. Preserve all-or-nothing sealing/enqueue and repeat-finalize idempotency. Use direct case clauses/with for import admission instead of nested conditionals and a file-wide nesting exemption.
5. Filter bound DatasetValues through record.root_revision.id. The authorized TaskInput already pins that revision, so loading the complete revision only to retrieve root_record_id is unnecessary. Preserve the binding filter, explicit optional absence, and Project/Task/Attempt authorization locks.

## Reviewed Boundaries Retained

- DatasetRecord.CreateValues deliberately batches both occurrence rows and typed children. Ash's nested relationship hooks execute per parent in bulk creation; replacing this with nested has-one writes would lose cross-record typed-child batching.
- Dataset fingerprints have a persisted versioned canonical encoding. Replacing their byte framing with term encoding would change identity, so retain it.
- Form graph validation and project activation enforce cross-resource publication rules under owner locks. Local Ash validations cannot replace those rules or locks.
- Task allocation/review/export retain their distinct lock scopes, immutable snapshot membership, and streamed output. Removing these would change concurrency or retry behavior.
- OIDC metadata is validated before fetching its JWKS endpoint. A generic provider worker would need equivalent endpoint checks; the current small cache remains justified.
- S3 publication must bound streaming work, pin staging versions, enforce immutable writes, and check database claims. ExAws handles signing and supported control operations; the custom orchestration remains a real storage/database boundary.

## Risks / Trade-offs

- Shared expressions can accidentally change parent-reference scope: retain organization correlations at each caller and run direct and nested authorization suites.
- Streaming can skip rows or schedule partial work: retain stable source-position/ID ordering and test multiple pages, concurrent finalization, and rollback after scheduling failure.
- Error simplification can miss nested failures: cover nested classes, overlapping paths, positive/negative constraints and categories.

## Migration Plan

No migration or dependency update. Use the generated OpenSpec change scaffold, edit existing modules, run focused checks and the complete verification gate, then commit.
