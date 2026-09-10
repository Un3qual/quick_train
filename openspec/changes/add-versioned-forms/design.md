## Context

See `proposal.md` for motivation and scope. The live repository has Accounts, organization capabilities, AshGraphql, normalized Datasets, and Assets. It has no Forms resources. The prior architecture record's sections A–C, I, M, and N establish reusable, normalized form contracts; its later opaque-file decision explicitly defers media interpretation and inline delivery.

The existing dataset schema actions demonstrate `Ash.transact`, parent-row locking, scoped child resolution, and serialized version-number allocation. Reuse those Ash patterns in Forms without refactoring Datasets or introducing a generic versioning framework. Existing PostgreSQL typed-child constraints demonstrate the repository's narrow migration-level exception for relational invariants.

## Goals / Non-Goals

**Goals:** Keep a form version a self-contained, bounded graph that can be inspected and later pinned by immutable identity. Make draft edits and publication share one transactional boundary. Enforce relational ownership and published immutability beneath the public API.

**Non-Goals:** See the proposal's exclusions. In particular, a published form is a structurally valid definition, not a promise that a Projects/Tasks executor or safe image renderer already exists. Do not add placeholder domains for those consumers.

## Decisions

### 1. A dedicated Forms domain with a small lifecycle

Add `QuickTrain.Forms` using Ash generators and existing AshPostgres/AshGraphql conventions. Form stores organization, immutable key, and identity; authored title and description belong to FormVersion so publication freezes all task-visible metadata. Versions contain a positive number, `draft | published` state, and nullable publication timestamp. Organization ownership, parent identity, version number, and authored keys cannot be changed after creation; keys can be replaced by deleting and recreating unreferenced draft definitions.

Use explicit create-form, create-draft, update-draft, copy-published-version, definition-edit, reorder, and publish actions. Allow multiple drafts, matching the existing dataset version model. Copy accepts only a published source from the same form; no mutable-source snapshot protocol is needed. Published-to-draft copying maps old child IDs to new IDs in dependency order inside one transaction. Neither form nor version deletion is public in this change. Removing an unreferenced draft definition is supported; removing a referenced definition fails until the author removes its references.

**Alternatives:** A single editable form plus revision history would complicate future pinned references. Allowing draft-to-draft copying adds source-edit races with no identified need. A separate lifecycle workflow engine or cross-domain versioning library would add indirection to two simple states.

### 2. Relational ownership and typed definitions

The graph is:

```text
Form -> FormVersion
          -> InputSlotDefinition -> InputFieldRequirement
          -> PresentationElement -> one typed presentation child
          -> QuestionDefinition -> typed constraints and choice/source references
                                -> QuestionOption (static choices only)
          -> LabelSet -> Label
```

Use one version owner on every descendant, with composite foreign keys ensuring intermediate parents and referenced records share that version. UUID primary keys remain stable external identities. Ash identities and database unique constraints cover form keys per organization, version numbers per form, definition keys in their documented scopes, and ordered positions per parent. Restrict foreign-key deletion; do not cascade through published graphs. Descendant ownership and parent IDs are immutable even in drafts, so moving a question or option between parents is expressed as explicit creation and removal.

PresentationElement stores kind and position. Typed children hold plain text for instruction, heading, and section variants, a field-requirement relationship for bound values, or a question relationship for question placement. A transactional public write creates a complete element and matching child; deferred relational checks enforce exactly one matching subtype at commit. A section is a flat marker, not a nested tree. Bound values describe all eventual task inputs in the referenced slot; actual per-attempt ordering belongs to Tasks.

QuestionDefinition stores key, prompt, family, and renderer. Use typed resources for TextConstraints, IntegerConstraints, DecimalConstraints, SelectionConstraints, and AnnotationConstraints. Boolean and ranking need no empty constraint table; ranking references its slot and always ranks all items. Selection constraints cover the single/multiple count contract; static options remain QuestionOption rows, and dynamic selections use slot relationships. Annotation constraints reference one source requirement and one label set and hold min/max count; coordinate and offset conventions are fixed by the spec, not configurable blobs. Enforce one applicable constraint resource and prohibit unrelated typed children. Draft creation and family changes may temporarily leave required constraint children absent, but never admit a wrong-family child. Publication requires the complete set.

Question-family and renderer compatibility is the closed matrix in the capability spec. Family or renderer changes reject incompatible existing children and require explicit removal or compatible replacement first. Source field updates also validate inbound question relationships under the same version lock. Integer question bounds use the existing signed 32-bit GraphQL Int range, including implicit endpoints for omitted bounds; no custom scalar is introduced. Static option labels must contain at least one non-whitespace character, checked on creation and update. Single-choice bounds are fixed at one. Multi-choice limits are feasible for every allowed slot size, and ranking has no partial-ranking toggle. Labels are version-owned and optionally shared by questions in that version; no external label library or automatic cross-version identity matching is added.

**Alternatives:** JSONB configuration and a universal key/value constraint table obscure typed references and integrity. A separate table for every renderer duplicates shared answer contracts. A mutable shared label library would change published meaning; copying version-owned labels avoids that dependency.

### 3. Inputs describe requirements without depending on concrete content

Input slots specify min/max item counts; field requirements specify one value family, single cardinality, and requiredness. Their families align with current dataset scalar/asset families, but Forms owns its contract and stores no dataset foreign keys. Do not extend dataset cardinality or nested records. The distinction permits `candidate × 2` while retaining single-valued fields per candidate.

Asset requirements have intended use `download | image`; non-asset requirements have no asset-use value. Image intent is only a declaration for a later compatibility check. Do not infer file safety from a declared MIME type or nullable dimensions, resolve assets while publishing, issue asset descriptors through Forms, or restore file sniffing. Text spans declare code-point offsets with exclusive ends; actual bounds validation needs immutable source text and belongs to response submission. Spatial definitions likewise defer source dimensions and geometry validation to Tasks plus the separately scoped rendering change.

**Alternative:** Concrete dataset field IDs inside forms would prevent reuse and reverse the recorded dependency direction. Serving images as part of form authoring would contradict the current asset contract and couple definition publication to an unselected storage/rendering integration.

### 4. Serialize every draft write and publication on FormVersion

Public actions authorize using the existing organization-capability check, then use `Ash.transact` with an organization-scoped `FOR UPDATE` read of the owning version. Resolve children again under that lock. Validate state, related references, inbound compatibility, and count limits after locking. All writes, including removal, reorder, options, constraints, labels, and metadata, follow this boundary. Internal low-level actions remain unexposed and are used only within the authorized transaction.

Publication locks the version, loads its bounded full graph through internal scoped reads (not a default first page), validates every spec invariant, and writes state and timestamp together. Already-published retries return the existing record after authorization. Failed publication rolls back without modifying graph content. Draft-number allocation locks Form and computes the next number from committed versions with a database uniqueness backstop. Allocation commits with the new version; rollback consumes no number and returns no destination version. The non-recycling guarantee applies to committed versions, so no reservation records, tombstones, or per-form sequences are needed. Copy locks Form for allocation; its published source cannot change. No version-write path subsequently locks Form, avoiding inverse lock order.

Add narrowly scoped PostgreSQL guards for parent immutability and descendant insert/update/delete. A descendant guard locks its version, rejects a published owner, and prohibits reparenting using both old and new ownership values. The parent guard rejects mutation or deletion once published and invalid lifecycle transitions. This protects internal bypass paths and closes publication races even when a child write bypasses the action wrapper. Use database constraints for same-version references, valid bounds, position uniqueness, and subtype integrity. Full publication completeness and renderer compatibility remain owned by the deliberate Ash publication action; public/internal generic actions cannot set publication state outside it.

Custom SQL is justified only for these database invariants that ordinary Ash validations cannot guarantee against bypass or concurrent writes. Keep it Forms-specific, with reversible migrations and focused SQL boundary tests. Do not introduce raw Ecto queries into product actions or a generic trigger generator.

For a reorder, require the complete current child ID set under the version lock, then atomically assign consecutive positions starting at zero in the supplied ID order, canonicalizing any old gaps while preserving record identities. Use a deferrable position-uniqueness constraint for swaps if the generated schema requires it; do not expose transient positions or persist fractional-order schemes. Option and label ordering use the same operation contract on their respective parents.

**Alternatives:** An unlocked state precheck permits a late edit after publication. Optimistic locking each child does not coordinate the entire graph. Holding a global form lock on every child edit unnecessarily serializes independent drafts.

### 5. Explicit authorization and bounded GraphQL

Provision `forms.read` and `forms.manage` using the existing `QuickTrain.Authorization.create_capability` primitive and extend the test-only composition in `test/support/data_case.ex`. Document explicit operator use of the existing capability and role-grant primitives for deployments; there is no production bootstrap convenience action to extend, and restoring one remains deferred to `restore-operator-bootstrap-and-maintenance`. Do not grant them to arbitrary existing roles or conflate them with dataset privileges. Apply the existing organization capability policy to public actions; nested resource reads must also be anchored to an authorized parent and its owning organization. Mutation-result access is limited to the returned authorized graph; it cannot become a general read bypass for managers lacking `forms.read`.

Integrate Forms into the existing GraphQL schema. Expose typed lifecycle actions and typed resource relationships; disable automatic unrestricted filters, sorting, and writes as in Datasets. Lists and nested collections use cursor pagination, default 50 and maximum 100, and existing query-complexity accounting. Ordered collections sort by position then ID; other collections use stable creation time and ID, with versions ordered by number. A multi-request traversal of an actively edited draft is not a snapshot; published traversals are stable.

Keep synchronous authoring and publication bounded. Initial named application limits are 32 slots, 64 requirements per slot, 200 questions, 1,000 presentation elements, 200 options per question, 100 label sets, 200 labels per set, 100 items per slot, and 10,000 owned rows total per version, including constraint/subtype rows. Keys have a 512-byte maximum; names, titles, and option/label text 1,024 bytes; prompts, instructions, and descriptions 16 KiB each. Reject NUL and invalid UTF-8. Apply finite application/request body limits before decoding large payloads, then graph limits inside the locked transaction. Copy uses the same destination limits and fails atomically if an older source exceeds current limits. Publication issues are sanitized and capped at 100 entries with a truncation indicator. These defaults are documented implementation choices; changing them must preserve bounded behavior and the validity of already-published reads.

**Alternatives:** Returning the entire graph recursively defeats API complexity limits. Background publication adds a lifecycle and failure recovery system despite a bounded graph. A public schema-only worker read shortcut would prematurely implement the separate project-worker eligibility path.

## Risks / Trade-offs

- **[Definition breadth without execution]** -> Support the recorded scalar, choice, ranking, and annotation contracts, but make publication semantics explicit. No media execution or answer validation is claimed by this release.
- **[Normalized graph needs several tables]** -> Generate resources and migrations, share only actual family behavior, and omit empty boolean/ranking constraint tables and future response resources.
- **[Graph edits race publication or reference changes]** -> One version lock, restrictive foreign keys, narrow database guards, and independent-connection race tests.
- **[Database guards become a second implementation]** -> Limit them to durable integrity and immutability; keep product validation and lifecycle orchestration in Ash.
- **[Large graphs cause slow publication or copies]** -> Bound row counts and text sizes, load all pages deliberately, and keep storage/network I/O out of these transactions.

## Migration Plan

1. Generate Forms resources, additive migrations, and resource snapshots with the pinned toolchain. Add constraints and immutability guards, then inspect generated SQL and migration ordering.
2. Integrate GraphQL and document capability provisioning through the existing primitive actions and test fixture. Existing dataset, asset, account, and role data require no transformation or implicit grants. The change does not depend on the deferred operator-maintenance work.
3. Verify fresh database creation, focused policy/lifecycle/GraphQL tests, independent-connection races, and the full repository gate before merge. Synchronize all OpenSpec tasks and specs with any implementation decisions.
4. Before production use, rollback can remove the additive schema through verified down migrations. After published forms exist, prefer reverting application exposure while retaining their tables and evidence; destructive schema rollback requires a separate data-retention decision.
