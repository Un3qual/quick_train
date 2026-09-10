## Why

Organizations can now ingest immutable dataset content, but cannot define the reusable input and question contract needed to collect work against it. Versioned forms let authors publish one stable task definition that future projects can bind to many dataset items without copying forms or questions per item.

## What Changes

- Add organization-owned Forms and numbered FormVersions with editable drafts and an irreversible, atomic publication boundary.
- Define reusable input slots and typed field requirements independently of concrete datasets, item revisions, and dataset field IDs.
- Store one ordered presentation sequence with typed instruction, heading, section, bound-value, and question-placement elements.
- Define typed scalar, static-choice, task-input-choice, ranking, and annotation question contracts, separating renderer type from answer family. Keep static options, input-slot references, label sets, labels, and family-specific constraints relational.
- Expose scoped authoring and paginated inspection through deliberate AshGraphql actions protected by `forms.read` and `forms.manage`.
- Keep lifecycle, ownership, subtype compatibility, and publication rules in Ash/Elixir; PostgreSQL provides relational constraints and transactional locks.
- Preserve published child identities and content through authoring actions, including under concurrent authoring and publication. Support creating an empty draft or copying a published version of the same form into a new draft.

Explicit non-goals:

- Projects, dataset bindings or activation, task selection, worker access, attempts, answer persistence, submission validation, review, exports, finance, or reputation.
- Frontend rendering, external forms, inline asset delivery, format sniffing, image decoding, safe-rendering certification, or an HTTP storage adapter. Media and annotation definitions describe future task contracts only.
- Conditional branching, computed fields, arbitrary nested form layouts, reusable cross-version label libraries, schema plugins, JSONB configuration, or automatic version migration.
- Editing, unpublishing, or deleting published versions; form deletion and archival workflows.

## Capabilities

### New Capabilities

- `versioned-forms`: Organization-scoped form authoring, immutable publication, reusable typed inputs, normalized presentation and question contracts, and GraphQL inspection.

### Modified Capabilities

None. Existing authentication, dataset, and opaque asset-delivery contracts remain authoritative.

## Impact

- Adds `QuickTrain.Forms`, Ash/AshPostgres resources, generated migrations and snapshots, capability registration, GraphQL schema integration, and focused tests.
- Intentionally extends the reusable backend foundations with the Forms product domain already recorded in `record-future-product-architecture` sections A–C, I, M, and N. Accounts remain one global User with optional organization membership; managing forms requires membership and capability in the owning organization.
- Depends on existing account authentication and organization authorization. Forms declare requirements without reading or owning dataset content or storage access.
- Uses the existing stable, pinned toolchain and dependencies. No new dependency, job system, generic service layer, or runtime changes are part of this planning commit.
