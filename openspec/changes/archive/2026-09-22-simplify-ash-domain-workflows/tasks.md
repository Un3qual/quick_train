## 1. Approved audit fixes

- [x] 1.1 Bound OIDC metadata requests and route cache failures through login cleanup; verify timeout behavior.
- [x] 1.2 Convert dataset schema and child authoring to native actions, preserving locks and updating domain/GraphQL consumers.
- [x] 1.3 Convert form copy/publication to native actions and update consumers, preserving idempotency and rollback.
- [x] 1.4 Declare import opening as a native upsert with immutable retry facts and update consumers.
- [x] 1.5 Reuse Accounts interfaces and add scoped import lock/internal-write domain interfaces.
- [x] 1.6 Replace two completion updates with one conditional atomic update and verify mixed deadlines.
- [x] 1.7 Use an existence query for unsupported question contracts during activation.
- [x] 1.8 Align attempt policies and generated permission checks with active owner eligibility; retain post-lock checks.
- [x] 1.9 Share strict Ash-backed dataset scalar normalization and verify finite decimals and input/error semantics.
- [x] 1.10 Limit incoming field loads to required/supplied fields and candidate loads to actual value definitions.
- [x] 1.11 Resume published export assets without generating another temporary file; retain byte verification.
- [x] 1.12 Scope Task state loading to presentation consumers while retaining public state behavior.
- [x] 1.13 Batch distinct text-span sources and length calculations once per submission.

## 2. Integration and closeout

- [x] 2.1 Synchronize canonical specifications and new delta specifications with native API and failure behavior.
- [x] 2.2 Run focused tests and independent review, resolving all actionable findings.
- [x] 2.3 Run mise run openspec.validate and mise run verify, record any external blockers, and commit the verified work.

## 3. Approved security closeout

- [x] 3.1 Apply the minimum stable Ash and Mint security patches while preserving unrelated dependency and toolchain versions.
- [x] 3.2 Pass independent OpenSpec validation and the full verification gate without audit exceptions and record the results for archiving both completed simplification changes.

## Verification

- Reviewed and implemented all thirteen findings against baseline `93cbe41` on `codex/simplify-ash-workflows`.
- Independent reviews covered the native Forms/Datasets transactions and authentication/attempt policies. The malformed-field-key hydration regression found during review was fixed with direct-write and import-row coverage.
- `mise run openspec.validate`: 16 items passed.
- `mise run verify`: compilation, formatting, Ash code generation, boundary/compile-cycle checks, Credo, ExDNA, Reach, and Dialyzer passed. The dependency audit stopped the aggregate gate on the existing pinned packages:
  - Ash 3.33.0: `EEF-CVE-2026-86338` / `GHSA-7qr8-wrvq-566q`.
  - Mint 1.10.0: `EEF-CVE-2026-82672` / `GHSA-rj5m-69wp-cxq9`.
- Ran the remaining stages independently: `MIX_ENV=prod mix compile --warnings-as-errors` passed; `MIX_ENV=test QUICK_TRAIN_TEST_DATABASE_NAME=quick_train_c209_verify mix test` passed all 374 tests (seed 468451).
- Native mutation envelopes and record-first update/destroy domain calls are covered by updated API and fixture consumers. No database migration was generated. Dependency upgrades were excluded from the initial implementation; section 3 records the subsequently approved security closeout.

## Verification before security updates — 2026-09-22

- All six delta specifications match the canonical requirements. No specification merge is needed.
- `mise run openspec.validate`: 16 items passed.
- `mise run verify`: compilation, formatting, Ash code generation, boundary/compile-cycle checks, Credo, ExDNA, Reach, and Dialyzer passed. The dependency audit was blocked by the Ash and Mint advisories recorded above.
- Ran the remaining gate stages independently: production compilation with warnings as errors passed; all 374 tests passed on the fresh `quick_train_c8c4_closeout` database (seed 714537).

## Final closeout — 2026-09-22

- Updated the exact Ash requirement to 3.33.4 and the transitive Mint lock to 1.10.1, the minimum stable patches for the two advisories. No other lock entries or mise toolchain pins changed.
- Independent `mise run openspec.validate` passed all 16 active changes/specifications before archival.
- `QUICK_TRAIN_TEST_DATABASE_NAME=quick_train_c8c4_closeout mise run verify` passed the complete gate without exceptions, including production compilation, a clean dependency audit, and all 374 tests (seed 203515).
- All eight added requirements match the canonical specifications. No specification merge is needed for archival.
