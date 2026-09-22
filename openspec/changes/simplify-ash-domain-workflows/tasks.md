## 1. Approved audit fixes

- [ ] 1.1 Bound OIDC metadata requests and route cache failures through login cleanup; verify timeout behavior.
- [ ] 1.2 Convert dataset schema and child authoring to native actions, preserving locks and updating domain/GraphQL consumers.
- [ ] 1.3 Convert form copy/publication to native actions and update consumers, preserving idempotency and rollback.
- [ ] 1.4 Declare import opening as a native upsert with immutable retry facts and update consumers.
- [ ] 1.5 Reuse Accounts interfaces and add scoped import lock/internal-write domain interfaces.
- [ ] 1.6 Replace two completion updates with one conditional atomic update and verify mixed deadlines.
- [ ] 1.7 Use an existence query for unsupported question contracts during activation.
- [ ] 1.8 Align attempt policies and generated permission checks with active owner eligibility; retain post-lock checks.
- [ ] 1.9 Share strict Ash-backed dataset scalar normalization and verify finite decimals and input/error semantics.
- [ ] 1.10 Limit incoming field loads to required/supplied fields and candidate loads to actual value definitions.
- [ ] 1.11 Resume published export assets without generating another temporary file; retain byte verification.
- [ ] 1.12 Scope Task state loading to presentation consumers while retaining public state behavior.
- [ ] 1.13 Batch distinct text-span sources and length calculations once per submission.

## 2. Integration and closeout

- [ ] 2.1 Synchronize canonical specifications and new delta specifications with native API and failure behavior.
- [ ] 2.2 Run focused tests and independent review, resolving all actionable findings.
- [ ] 2.3 Run mise run openspec.validate and mise run verify, record any external blockers, and commit the verified work.
