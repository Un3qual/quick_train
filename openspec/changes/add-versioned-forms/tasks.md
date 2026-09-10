## 1. Generate Forms resources and relational structure

- [x] 1.1 Use repository-pinned Ash generators through `mise` to create `QuickTrain.Forms`, Form, and FormVersion with organization ownership, stable keys, numbered versions, version metadata, and draft/published state; deliberately restrict generated default actions.
- [x] 1.2 Generate input-slot and field-requirement resources, then add version-scoped relationships, keys, slot count bounds, single field cardinality, value-family enums matching datasets (including `utc_datetime` for UTC values), requiredness, and asset intended use restricted to asset-family requirements on create/update and family changes.
- [x] 1.3 Generate presentation elements and typed text/reference subtypes; add nonblank instruction/heading text, ordered positions, flat section markers that permit unnamed sections, same-version field/question references, and matching-subtype integrity.
- [x] 1.4 Generate question definitions with nonblank prompts enforced on creation and update, and typed text, integer, decimal, selection, and annotation constraints; add signed 32-bit integer bounds with implicit endpoints only for `integer_input`, plus explicit stars/Likert bounds at publication and a 200-value maximum range and the specified renderer/family matrix and omit empty constraint tables for boolean and ranking.
- [x] 1.5 Generate static options, version-owned label sets, and labels; add dynamic slot/source references separately from static options and enforce parent-scoped keys, nonblank static option labels and annotation label display text, and ordering.
- [x] 1.6 Generate and review additive AshPostgres migrations and snapshots; add restrictive/composite foreign keys, unique identities, signed 32-bit checks for all exposed integer fields plus tighter domain bounds, subtype checks, immutable ownership, and the position-constraint support required for atomic reorder.

## 2. Authorize and serialize draft authoring

- [x] 2.1 Document provisioning of `forms.read` and `forms.manage` with the existing Authorization capability and role-grant primitives, extend the test-only fixture, and leave the deferred operator bootstrap unimplemented, with no implicit grants to unrelated roles; add public-action and nested-read policies using the existing active-account, organization, membership, and capability path.
- [x] 2.2 Implement create-form and create-empty-draft actions by locking the owning Form before reading/allocating the next version and holding the lock through commit or rollback; consume numbers only for committed versions and preserve immutable form/version identity; permit multiple drafts without exposing form or version deletion.
- [x] 2.3 Implement a Forms-specific Ash transaction boundary that locks and resolves the organization-owned draft before every metadata or child write and revalidates its state and related references under that lock.
- [x] 2.4 Implement typed draft definition creation, editing, and unreferenced removal with input/renderer/family/source compatibility validation; reject incompatible inbound reference changes and never silently discard typed children.
- [x] 2.5 Implement complete-permutation reorder actions for presentation elements, question options, and labels, with atomic canonicalization to consecutive positions starting at zero and scoped ID-set validation, preserving record identities.
- [x] 2.6 Add and document the design's finite graph, item-count, text (including the 1,024-byte heading/section-marker limit), request-size, and sanitized-error limits; enforce destination limits during ordinary authoring and copying without changing published inspection.

## 3. Publish and copy immutable contracts

- [x] 3.1 Implement publication validation over the complete bounded graph, including rows beyond the first page: nonblank title, input requirements, one placement per question, typed children, choice feasibility, source/label compatibility, bounds, keys, and positions.
- [x] 3.2 Implement atomic draft-to-published transition and authorized idempotent publication retries under the same version lock; preserve graph state on failure and freeze the publication timestamp.
- [x] 3.3 Add narrowly scoped database guards for published parent/descendant insert, update, delete, and ownership changes, using the same parent lock to protect internal bypass paths; keep product publication validation in Ash.
- [x] 3.4 Implement copying a same-form published version to a new numbered draft while holding the same owning Form allocation lock from before reading the next number through commit or rollback, remapping all owned identities and references in dependency order; reject draft and foreign sources and roll back partial copies.

## 4. Expose deliberate GraphQL operations

- [x] 4.1 Integrate Forms into the existing AshGraphql schema with scoped create, draft-edit, reorder, copy, publish, and inspection operations; keep unrestricted internal actions and future worker/response operations private.
- [x] 4.2 Expose typed constraints and references plus version identity/state/timestamp; paginate every top-level and nested collection with the specified limits and stable order, including query-complexity accounting.
- [x] 4.3 Preserve authorization on mutation results and nested reads, including managers without general read capability; return sanitized scoped validation errors and no dataset content or asset descriptors.

## 5. Verify meaningful behavior and concurrency

- [x] 5.1 Test a successful single-item rating contract (one-item slot and an integer question using the stars renderer with bounds 1–5), static-choice, pairwise, ranking, text-span, and spatial-definition contracts; cover representative invalid renderer, source, signed 32-bit endpoints and overflow for answer bounds, text-length/annotation-count metadata, positions, and version allocation, bounds, cardinality, empty/whitespace-only question prompts, instruction/heading text, and option/annotation labels, asset intent on non-asset fields and family changes, omitted and oversized stars/Likert bounds plus the 200-value boundary, UTC family naming, placement, and cross-version-reference cases with focused parameterized tests.
- [x] 5.2 Test all authorization failure classes, cross-organization IDs, nested relationship reads, read-only callers, and manage-only mutation results through Ash and authenticated GraphQL.
- [x] 5.3 Test complete copy/remapping and source immutability, copy rollback without number consumption, invalid source rejection, draft repair after failed publication (including empty and whitespace-only titles), and stable repeated publication results.
- [x] 5.4 Use independent database connections and deliberate barriers to test concurrent version allocation across empty creation and copying (including allocation rollback while another request waits, with strictly increasing committed numbers), publication/publication, child edit/publication in both orders, and referenced-source edit races; assert serialized valid outcomes rather than timing assumptions.
- [x] 5.5 Test published insert/update/delete/reparent rejection through direct persistence paths, typed-child and same-version database integrity, and rollback of incomplete transactional writes.
- [x] 5.6 Test reorder permutations and sparse-to-consecutive atomic swaps, later-page publication validation and nested pagination, graph/request limits including heading and section-marker text at and above 1,024 UTF-8 bytes, and the absence of data or storage access from form inspection; keep tests behavioral rather than source-shape assertions.
- [x] 5.7 Verify additive migrations on a fresh test database and their down/up behavior on disposable data; inspect generated migration and snapshot consistency and compile through the repository toolchain.

## 6. Final validation and closeout

- [x] 6.1 Reconcile implementation decisions with this proposal, design, capability spec, and task checklist while preserving the deferred Projects, Tasks, and media-rendering boundaries.
- [x] 6.2 Run `mise run openspec.validate` independently and resolve all findings attributable to this change.
- [x] 6.3 Run `mise run verify`, resolve failures attributable to this change, and record any external blockers before reporting implementation complete or merging.

## 7. Approved Ash cleanup

- [ ] 7.1 Replace ordinary generic mutations with named create/update/destroy actions and shared transaction hooks, preserving scoped locking, partial updates, and publication semantics.
- [ ] 7.2 Expose Forms domain code interfaces and use them in callers and fixtures.
- [x] 7.3 Use bulk Ash operations for reorder and copy while retaining graph bounds, dependency order, and rollback.
- [x] 7.4 Centralize common PlainText constraints in its existing Ash NewType.
- [x] 7.5 Use relationship metadata for copy remapping and Ash cascade destruction for presentation children.
- [x] 7.6 Replace membership enumeration in nested authorization with a relational eligibility filter.
- [ ] 7.7 Reconcile the GraphQL contract and design, then rerun focused behavior/concurrency tests and the full verification gate.

## Verification record

- `mise run verify` passed with 205 tests, including 48 Forms tests. The gate also passed
  compilation, formatting, Ash code-generation consistency, boundary/cycle checks, static
  analysis, Dialyzer, the dependency audit, and production compilation.
- `mise run openspec.validate` passed independently for all seven current changes/specifications.
- Fresh migrations and Forms down/up completed on a disposable database containing a published
  rating graph; that database was removed afterward.
- The maximum 10,000-row graph was published and copied successfully. Independent-connection
  race tests observed actual PostgreSQL blocking before allowing the first transaction to finish.
- No dependency changes, external blockers, or deferred implementation tasks remain in this change.
