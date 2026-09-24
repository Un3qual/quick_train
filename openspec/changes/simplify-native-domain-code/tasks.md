## 1. Simplify native domain code

- [x] 1.1 Generate the OpenSpec change scaffold, document the review, and share the Ash capability expression and subject lookup while preserving fail-closed scoping.
- [x] 1.2 Remove redundant string normalization and intermediate error presentation traversal; exercise the existing normalization contract and nested structured errors.
- [x] 1.3 Stream import scheduling in bounded batches and flatten admission branches while retaining locking, idempotency, and rollback behavior.
- [x] 1.4 Replace the revision-to-record lookup with an Ash relationship filter and verify pinned values, optional absence, and concurrent access revocation.

## 2. Verify and commit

- [x] 2.1 Run focused authorization, normalization, import, and error-classification tests; review the diff and commit the verified simplifications.
- [x] 2.2 Run independent mise run openspec.validate and the full mise run verify gate, record the evidence and final code reduction, and commit closeout.

## Verification

- Reproduced the overlapping error-path crash before editing the classifier; both structured-error tests pass after the fix.
- Focused authorization, account/organization, import, schema, asset, task-read/result, and GraphQL suites: 111 tests passed (seed 571771).
- After replacing the bound-value lookup, the task-read and collection GraphQL suites passed all 21 tests (seed 623786), including concurrent revocation.
- Independent OpenSpec validation: all 16 active changes/specifications passed. Formatting and diff whitespace checks passed.
- Full `mise run verify` passed: compilation, formatting, Ash code generation, boundaries, compile dependency cycles, Credo, duplication/architecture checks, Dialyzer, dependency audit, and production build.
- The full backend suite passed all 411 tests (seed 116048); the disposable HTTPS storage integration suite passed all 24 tests (seed 87951).
- Production code is 40 lines shorter across ten modules. No dependency, schema, or public API changes.
