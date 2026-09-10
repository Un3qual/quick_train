## 1. Generate Forms resources and relational structure

- [ ] 1.1 Use repository-pinned Ash generators through `mise` to create `QuickTrain.Forms`, Form, and FormVersion with organization ownership, stable keys, numbered versions, version metadata, and draft/published state; deliberately restrict generated default actions.
- [ ] 1.2 Generate input-slot and field-requirement resources, then add version-scoped relationships, keys, slot count bounds, single field cardinality, value-family enums, requiredness, and asset intended use.
- [ ] 1.3 Generate presentation elements and typed text/reference subtypes; add ordered positions, flat section markers, same-version field/question references, and matching-subtype integrity.
- [ ] 1.4 Generate question definitions and typed text, integer, decimal, selection, and annotation constraints; add the specified renderer/family matrix and omit empty constraint tables for boolean and ranking.
- [ ] 1.5 Generate static options, version-owned label sets, and labels; add dynamic slot/source references separately from static options and enforce parent-scoped keys and ordering.
- [ ] 1.6 Generate and review additive AshPostgres migrations and snapshots; add restrictive/composite foreign keys, unique identities, bound checks, subtype checks, immutable ownership, and the position-constraint support required for atomic reorder.

## 2. Authorize and serialize draft authoring

- [ ] 2.1 Register `forms.read` and `forms.manage` through the existing capability setup, with no implicit grants to unrelated roles; add public-action and nested-read policies using the existing active-account, organization, membership, and capability path.
- [ ] 2.2 Implement create-form and create-empty-draft actions with serialized version allocation and immutable form/version identity; permit multiple drafts without exposing form or version deletion.
- [ ] 2.3 Implement a Forms-specific Ash transaction boundary that locks and resolves the organization-owned draft before every metadata or child write and revalidates its state and related references under that lock.
- [ ] 2.4 Implement typed draft definition creation, editing, and unreferenced removal with input/renderer/family/source compatibility validation; reject incompatible inbound reference changes and never silently discard typed children.
- [ ] 2.5 Implement complete-permutation reorder actions for presentation elements, question options, and labels, with atomic position swaps and scoped ID-set validation.
- [ ] 2.6 Add and document the design's finite graph, item-count, text, request-size, and sanitized-error limits; enforce destination limits during ordinary authoring and copying without changing published inspection.

## 3. Publish and copy immutable contracts

- [ ] 3.1 Implement publication validation over the complete bounded graph, including rows beyond the first page: title, input requirements, one placement per question, typed children, choice feasibility, source/label compatibility, bounds, keys, and positions.
- [ ] 3.2 Implement atomic draft-to-published transition and authorized idempotent publication retries under the same version lock; preserve graph state on failure and freeze the publication timestamp.
- [ ] 3.3 Add narrowly scoped database guards for published parent/descendant insert, update, delete, and ownership changes, using the same parent lock to protect internal bypass paths; keep product publication validation in Ash.
- [ ] 3.4 Implement copying a same-form published version to a new numbered draft in one transaction, remapping all owned identities and references in dependency order; reject draft and foreign sources and roll back partial copies.

## 4. Expose deliberate GraphQL operations

- [ ] 4.1 Integrate Forms into the existing AshGraphql schema with scoped create, draft-edit, reorder, copy, publish, and inspection operations; keep unrestricted internal actions and future worker/response operations private.
- [ ] 4.2 Expose typed constraints and references plus version identity/state/timestamp; paginate every top-level and nested collection with the specified limits and stable order, including query-complexity accounting.
- [ ] 4.3 Preserve authorization on mutation results and nested reads, including managers without general read capability; return sanitized scoped validation errors and no dataset content or asset descriptors.

## 5. Verify meaningful behavior and concurrency

- [ ] 5.1 Test successful single-rating, static-choice, pairwise, ranking, text-span, and spatial-definition contracts; cover representative invalid renderer, source, bounds, cardinality, label, placement, and cross-version-reference cases with focused parameterized tests.
- [ ] 5.2 Test all authorization failure classes, cross-organization IDs, nested relationship reads, read-only callers, and manage-only mutation results through Ash and authenticated GraphQL.
- [ ] 5.3 Test complete copy/remapping and source immutability, copy rollback, invalid source rejection, draft repair after failed publication, and stable repeated publication results.
- [ ] 5.4 Use independent database connections and deliberate barriers to test concurrent version allocation, publication/publication, child edit/publication in both orders, and referenced-source edit races; assert serialized valid outcomes rather than timing assumptions.
- [ ] 5.5 Test published insert/update/delete/reparent rejection through direct persistence paths, typed-child and same-version database integrity, and rollback of incomplete transactional writes.
- [ ] 5.6 Test reorder permutations and atomic swaps, later-page publication validation and nested pagination, graph/request limits, and the absence of data or storage access from form inspection; keep tests behavioral rather than source-shape assertions.
- [ ] 5.7 Verify additive migrations on a fresh test database and their down/up behavior on disposable data; inspect generated migration and snapshot consistency and compile through the repository toolchain.

## 6. Final validation and closeout

- [ ] 6.1 Reconcile implementation decisions with this proposal, design, capability spec, and task checklist while preserving the deferred Projects, Tasks, and media-rendering boundaries.
- [ ] 6.2 Run `mise run openspec.validate` independently and resolve all findings attributable to this change.
- [ ] 6.3 Run `mise run verify`, resolve failures attributable to this change, and record any external blockers before reporting implementation complete or merging.
