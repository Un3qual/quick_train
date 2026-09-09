## Context

See `proposal.md` for motivation and the three delta specs for behavioral requirements.

QuickTrain currently contains account, organization, authorization, enterprise identity, and GraphQL foundations but no product content domain. Product GraphQL exposure depends on the separate `add-api-authentication` change. Approved later Forms, Projects, Tasks, Finance, and Reputation decisions are preserved separately in `record-future-product-architecture`; they do not expand this change's requirements or tasks.

This change introduces Assets and Datasets plus programmatic dataset imports. The implementation must use Ash and AshPostgres, avoid JSONB content, preserve immutable history, and leave repeated and nested record values additive.

## Goals / Non-Goals

**Goals:**

- Add organization-owned asset and dataset domains.
- Normalize schemas, stable items, immutable revisions, records, value occurrences, and typed values.
- Support bounded idempotent imports with row provenance and partial completion.
- Use ordinary idempotent Oban retries rather than a custom processing scheduler.
- Preserve an additive path to repeated and nested record values.

**Non-Goals:**

- Implement authentication, later product domains, external form integration, task answers, or payment behavior.
- Choose a production storage vendor.
- Store dataset content or row payloads in JSONB.
- Implement nested input, repeated cardinality, or arbitrary recursive records now.

## Decisions

### 1. Keep Assets and Datasets as separate Ash domains

`QuickTrain.Assets` owns immutable binary-content identity and authorized storage access. `QuickTrain.Datasets` owns customer schemas, logical content, stable items, revisions, and imports. Datasets depend on Assets for asset-valued fields; Assets do not depend on Datasets.

The top-level `QuickTrain` boundary exports both domains and the storage behavior. Public resources use deliberate AshGraphQL actions with authorization enabled.

Alternatives rejected:

- One generic content domain would mix binary storage lifecycle with schema and revision lifecycle.
- Placing assets inside Datasets would create the wrong dependency for future raster-mask answers.
- A generic CRUD or service layer would obscure lifecycle and authorization boundaries.

### 2. Use immutable content-addressed asset metadata and a provider-neutral adapter

`Asset` contains organization ownership, lifecycle state, canonical SHA-256, byte size, media type, legacy nullable image dimensions (unset by MVP), internal staging and sealed keys, staging expiry, the minimal bounded finalizer-claim facts, and timestamps. Digests use Ash’s built-in binary type and stay as 32 raw bytes in Elixir, storage-adapter facts, and PostgreSQL. Asset registration validates and decodes caller-supplied lowercase hex once; GraphQL output and textual storage keys encode raw bytes to hex. Ready assets are immutable. A partial unique identity on organization and content hash applies only to ready assets so a failed upload does not permanently reserve the identity.

Registration obtains and validates capped staging access before inserting a pending asset. Adapter failure therefore leaves no asset row and needs no compensating database deletion. Access is returned only after the insert succeeds; storage I/O remains outside database transactions. Registration rejects a declared byte size above a finite positive configured limit before returning access to a unique writable staging object. Implementation selects, tests, and documents safe defaults using representative asset sizes rather than freezing unvalidated product limits in this design. Every staging access path enforces the declared byte-size cap through provider-native or adapter-controlled behavior before returning upload access; if the configured adapter cannot enforce it, registration fails closed instead of adding an uncapped fallback path. Finalization rechecks pinned staging and canonical-object sizes as defense in depth before reading content, without parsing or decoding files.

One idempotent adapter operation pins a staged version or fences further writes, computes and validates its hash and size, and only then conditionally publishes exactly those verified bytes at the organization-and-SHA-256 canonical immutable key. It reverifies the published canonical object before returning success. Every pending registration goes through this operation, even when canonical content already exists, so another registration cannot hide mismatched staging bytes. A conditional create or equivalent compare-and-converge operation ensures concurrent identical content resolves the same sealed location; an existing canonical object must be reverified against the exact pinned bytes before reuse. Mismatched staging bytes never create or occupy the declared canonical key. A per-registration sealed copy or an unpinned verify-then-copy sequence is invalid.

Finalization verifies only size and SHA-256. Files are opaque bytes; declared media type is immutable untrusted metadata, not a sniffed or validated format. No file parser, active-content denylist, image dimension extraction, or inline preview is part of MVP. HTTP storage providers must enforce attachment disposition, application/octet-stream, and nosniff on actual download responses. Descriptor request headers cannot enforce server responses. Existing nullable dimension columns remain unset; dropping and later restoring those columns is unnecessary migration churn. Future format-aware rendering is recorded in `record-future-product-architecture`.

Concurrent identical finalizations converge on one canonical ready asset and one canonical sealed object only when size and media type also match; the losing matching registration becomes `duplicate_content`, points to the canonical asset for resolution, owns no sealed copy, and retains its redundant staging object. Cross-organization content never shares authorization or sealed locations. Looking up an existing ready canonical asset needs no row lock because its content and lifecycle are immutable. The pending registration lock, claim checks, and ready-content unique identity still arbitrate concurrent finalization.

`QuickTrain.Assets.Storage` provides staging access, verify-and-seal, and short-lived reads. Reads target only sealed objects. Returned descriptors use encrypted transport and no-store/no-referrer handling, and must expire after the current time and no later than the requested expiry. Descriptor headers must contain nonempty UTF-8 string names and UTF-8 string values before registration persists an asset. Adapters must issue direct endpoints that cannot redirect, enforced through provider configuration. Clients receive descriptors directly, so the backend cannot intercept later HTTP redirects. The current in-memory adapter performs no HTTP requests; any future production adapter must establish this no-redirect property before it is supported.

Finalization obtains a bounded claim under the asset lock, checks live identity before publication and database transitions, and uses finite adapter deadlines. Retries probe and reverify existing canonical content before adopting it. Storage I/O occurs outside database transactions. Staging deletion and background publication recovery are deferred to `restore-operator-bootstrap-and-maintenance`; no cleanup markers, retirement callbacks, or publication-window metadata are retained.

Alternatives rejected:

- Database blobs would inflate backups and couple delivery to PostgreSQL.
- Public URLs would bypass authorization.
- Mutable object keys would invalidate historical revisions and later spatial responses.

### 3. Publish explicit immutable dataset schema versions

```text
Dataset
└── DatasetSchemaVersion
    └── DatasetRecordType
        └── DatasetFieldDefinition
```

`Dataset` is a stable organization-owned container. A schema version begins as draft and becomes immutable when published. Every record-type or field edit and publication locks the same schema-version row and rechecks its state, preventing a draft edit from committing after publication. Child edits find that row directly through organization-scoped Ash `exists` relationship filters, then reread the child after locking; they do not preload the child and its ancestors merely to locate the schema.

Each first-release published version designates exactly one of its record types as root. Field keys are unique within a record type. Initial value families are text, integer, decimal, boolean, UTC date-time, and asset. The only initial cardinality is `single`; required fields have exactly one occurrence and optional fields have zero or one. Cardinality and occurrence ordinal are persisted so repeated values can be added without replacing existing tables.

Alternatives rejected:

- Per-row inferred schemas make validation and reusable bindings unreliable.
- Customer-specific tables or PostgreSQL enums require migrations for customer data.
- Untyped fields defer failures until task execution.

### 4. Give every item stable identity and immutable revisions

```text
DatasetItem
└── DatasetItemRevision
    └── root DatasetRecord
        └── DatasetValue
            └── exactly one typed value child
```

An item has a UUID and optional customer external key unique within its dataset. A revision pins one same-dataset published schema version, the schema's designated-root record, a monotonic revision number, and a deterministic content fingerprint. Corrections create revisions rather than mutating content.

One responsibility-owned fingerprint module uses a versioned domain-separated length-prefixed encoding. Revision fingerprints include schema and root-type identities, then occurrences ordered by field identity and ordinal. Canonical typed bytes use validated UTF-8 text excluding PostgreSQL-unsupported NUL characters, minimal signed integers, normalized non-exponent decimals without insignificant zeroes or negative zero, one-byte booleans, UTC Unix microseconds, and immutable asset UUIDs. The digest stays as 32 raw bytes internally and in PostgreSQL, and GraphQL output encodes it as lowercase hexadecimal. Equivalent field order, decimal scale, and time-zone offsets converge; actual type or value changes diverge.

For an external key, revision creation atomically gets or creates the dataset-scoped item and then locks the authoritative row before comparing the latest schema-aware fingerprint and assigning a revision number. An identical record under a different schema creates a new revision.

### 5. Use a typed record envelope, not JSONB or an arbitrary tree

`DatasetRecord` is an immutable instance of one exact record type. `DatasetValue` identifies one field occurrence and ordinal. Exactly one typed child stores its value:

- `DatasetTextValue`
- `DatasetIntegerValue`
- `DatasetDecimalValue`
- `DatasetBooleanValue`
- `DatasetDateTimeValue`
- `DatasetAssetValue`

Ash construction resolves fields only within the record's exact type and creates the graph transactionally. Composite same-dataset, same-schema, exact-record-type, and designated-root foreign keys backstop those validations. A deferred PostgreSQL constraint trigger is the narrow approved database-boundary exception for enforcing exactly one compatible typed child at commit because ordinary checks cannot count subtype rows.

Repeated values later permit additional ordinals. Nested records later add a record-valued child pointing to another `DatasetRecord`. Existing root, occurrence, scalar, and asset rows remain valid; no migration to a generic tree is required.

Alternatives rejected:

- Nullable scalar columns on items make repeated and nested values awkward.
- JSONB loses relational typing and foreign keys.
- A fully generic self-referential EAV tree weakens understandable ownership and type invariants.

### 6. Keep imports relational and let Oban provide retry semantics

```text
DatasetImport
└── DatasetImportRow
    └── optional normalized candidate DatasetRecord
```

An authorized manager opens an import against one dataset and published same-dataset schema, appends bounded flat rows, and finalizes it. Batch identity is unique by organization, dataset, and caller idempotency key. Matching opens return one import; changed immutable parameters, including the initiating actor, conflict. After checking the published schema and its dataset/organization scope, opening uses an Ash upsert on the existing batch identity with no updated fields. It returns the original fingerprint for comparison and preserves phase, timestamps, and expiry even on sealed or expired retries. No dataset-wide lock or preliminary import lookup is needed. AshPostgres is configured to use `INSERT ON CONFLICT` rather than `MERGE`, whose concurrent inserts can raise a uniqueness error instead of converging.

The GraphQL append action accepts one flat row per call. Finite positive configured limits bound accepted rows per import, field entries per row, total scalar bytes per row, individual text bytes, and request bytes. Implementation selects, tests, and documents safe defaults from representative imports rather than freezing unvalidated product limits in this design. The fixed input type rejects arbitrary nesting and unsupported structures. Every request, count, and byte limit is checked before canonicalization, sorting, hashing, candidate construction, or row-identity reservation.

After structural acceptance, append computes a versioned fingerprint from the schema identity, row key, external-key presence marker and length-prefixed persisted UTF-8 value when present, source position, and canonical accepted field entries. Import-open and row fingerprints use the same 32-byte AshPostgres storage representation as the asset and revision digests. It preserves domain-invalid keys, selectors, duplicates, and scalar values without needing a total encoding for every possible malformed request tree. Equivalent field order, decimal scale, and UTC offsets converge; a changed non-null external key diverges.

Each accepted row stores its row key, source position, optional external key, fingerprint, and outcome. A valid row immediately creates an immutable normalized candidate graph; a domain-invalid row stores a terminal sanitized failure and no partial graph. Import plus row key and import plus source position are unique. Import plus non-null external key accepts only one row; competing rows fail before persistence. A keyless valid row uses its import-row UUID as its target item UUID.

Append and finalization lock the same import. An import persists only `open` or `sealed` phase plus immutable `open_expires_at`. First finalization seals the row set and inserts the complete unique row-job set in the same transaction. Expired imports reject work but retain their rows, candidates, and batch identity while cleanup is deferred.

First finalization atomically seals the import and inserts one bounded-retry row job for each pending row through `Oban.insert_all`, in batches of at most 1,000. The locked `open` to `sealed` transition is the sole enqueue boundary: concurrent or repeated finalizations observe `sealed` and cannot enqueue again. Oban Basic bulk insertion does not enforce worker uniqueness, so the worker has no independent uniqueness configuration or single-row enqueue path. All batches share the sealing transaction. A failure to insert that complete bounded job set rolls back sealing, so there is no separate fan-out job that can strand rows after partial enqueue. A row job locks its row, skips terminal outcomes, and atomically commits item revision and terminal outcome. Failure before commit leaves the row pending for ordinary Oban retry. Failure after commit but before job acknowledgement is safe because the retry observes the terminal row.

Import row workers retain bounded retries and atomic row/revision commits. Background recovery of discarded or cancelled jobs is deferred to `restore-operator-bootstrap-and-maintenance`; affected rows may remain pending and ordinary pruning may remove job evidence.

Batch counts and lifecycle are query calculations over indexed rows, not mutable snapshots. The import query derives total, pending, succeeded, unchanged, and failed counts. Import inspection also returns a bounded cursor-paginated row-outcome connection over those existing rows, including row key, source position, current outcome, sanitized errors, and any resulting item-revision reference. A sealed import is pending while any row is pending; otherwise it is completed, failed, or partially failed from terminal outcomes. This removes parent-row serialization from independent row completion.

Source-file adapters remain later additions. A future CSV or archive importer can register its source as an Asset and call the same row actions without creating another persistence model.

### 7. Depend on the authenticated actor boundary

`add-api-authentication` is implemented first. Dataset and asset actions require exact capability keys `assets.read`, `assets.manage`, `datasets.read`, `datasets.manage`, and `dataset_imports.manage`, plus an active user, organization, and membership. Operator setup and grant convenience actions are deferred to `restore-operator-bootstrap-and-maintenance`. Existing primitive Ash actions remain; tests compose them in a test-only fixture. No wildcard or implicit manager authority is introduced.

Shared expected dataset and asset failures use `QuickTrain.DatasetAssetError`; GraphQL error codes remain unchanged.

No product content is public. Cross-organization failures do not disclose whether a dataset, schema, import, item, revision, or asset exists.

### 8. Expose deliberate GraphQL lifecycle actions

Public operations cover asset registration, finalization and authorized access; dataset and draft-schema lifecycle; import open, append, finalize, derived progress, and bounded paginated row-outcome inspection; and paginated typed reads. Product resources use AshGraphQL's explicit relationship allowlists to expose useful singular relationships as the related typed resource and useful to-many relationships as Relay connections, including schema structure, dataset items and revisions, normalized record values, import rows and their resulting revisions, and duplicate assets' canonical resource. Destination primary reads fail closed through Ash's `accessing_from` policy check, and the primary reads used by to-many relationships provide bounded keyset pagination with stable sorts. Internal staging, organization membership, candidate records, and reverse bookkeeping relationships remain private. Every GraphQL collection, including a nested relationship collection, is bounded, keyset-paginated, and represented as a Relay connection; offset pagination and unbounded list results are not exposed. There are no generic mutations for ready asset content, published schemas, item revisions, records, or typed values.

Stable error codes include `forbidden`, `invalid_schema`, `invalid_value`, `asset_not_ready`, `asset_identity_conflict`, `idempotency_conflict`, `import_not_open`, and `import_expired`.

### 9. Lock the authority row for related-data correctness

Schema edits and publication lock the schema version. Revision creation locks the stable item. Append and finalization lock the import. Row processing locks the import row and then the target item only for its terminal transaction. Asset finalization locks the asset before changing lifecycle facts.

Ash actions, `Ash.DataLayer.transaction/5`, atomic changes, and row-locking queries are the default. Composite constraints and the typed-child trigger are narrow database backstops generated through AshPostgres; application code does not bypass Ash with direct Ecto writes.

### 10. Use responsibility-specific durable jobs

This change reuses the pinned Oban dependency for asset verification and import-row processing. Jobs carry resource identities, not content. One-time row-job insertion is enforced by the locked import phase transition; independently idempotent actions remain. All custom periodic bootstrap/maintenance workflows are deferred; built-in Oban retry, Lifeline, and pruning behavior remains.

QuickTrain does not recreate generic Operations, Integrations, Audit, or DurableDelivery domains.

### 11. Keep lifecycle entry points and record construction cohesive

Expected product failures use typed Ash errors with stable GraphQL codes. Unexpected exceptions retain the framework's sanitized response. Internal workers invoke resource actions through domain code interfaces with explicit authorization bypass for their already-authorized immutable resource identities; internal lifecycle actions are not exposed through GraphQL and fail closed for ordinary callers. Storage I/O remains outside database transactions.

Normalized-record validation and construction belong to DatasetRecord. Append and revision creation share that implementation rather than calling one another's action helpers. Processing reads typed occurrences directly from its immutable candidate and reuses that record as a new revision root; candidate provenance remains retained, and revision fingerprint and unchanged semantics stay identical. Raw revision input and import append validate distinct ready asset references in one organization-scoped query. Row processing trusts those references in its already-validated immutable candidate instead of querying the same ready assets again; it still checks the candidate organization, dataset, schema, and root type. Ready assets cannot transition or be deleted through the supported actions, and restrictive foreign keys preserve references.

Database race tests use independently checked-out connections and committed fixtures, with deterministic test teardown, so PostgreSQL uniqueness and row locks are exercised.

The dependency audit requires Ash 3.33.0 and Mint 1.10.0. Ash string-length constraints count Unicode codepoints, matching PostgreSQL; import payload limits continue to count bytes independently.

### 12. Validated simplifications against the future architecture

The deferred `record-future-product-architecture` design requires immutable dataset revisions and stable source value identities for task inputs and annotations (sections C, D, and I). It does not require separate copies of an import candidate and its revision graph. New imported revisions therefore reference the accepted immutable candidate directly. Unchanged imports keep their candidate provenance and point to the existing revision. Restrictive revision foreign keys protect referenced records; import cleanup is deferred.

Structural import validation remains separate from schema validation: malformed requests reserve no row identity, while domain-invalid inputs retain failed provenance. Schema binding consumes already-normalized entries directly. A single `Datasets.Fingerprint` module owns revision, import-row, and import-open encoding through named functions, retaining their separate domains and exact version-one bytes. Scalar and framing helpers stay private, except canonical decimal rendering used by structural byte limits. Datasets and assets use Ash’s built-in `:binary` type; no custom digest type is needed. Future response persistence stays separate; no cross-product type framework is introduced.

Tests use one `Storage.InMemory` adapter and its deterministic staging and inspection controls. Its token URLs are not HTTP endpoints. Development and production leave storage unconfigured and fail with `storage_not_configured` until a reachable provider adapter is selected. The adapter owns its GenServer directly; deadline accounting and initial content verification still execute in the calling process. Asset summaries derive their copied attribute names from the embedded Ash resource, which excludes storage keys and claims. Import row lookups share one Ash keyword filter scoped to the import identity.

OIDC race tests reuse the independent-connection helper, and GraphQL tests share their request/assertion helper in ConnCase.

Foundation GraphQL declarations and the metrics scaffold are explicitly retained for planned future work.

Cleanup-only record/value destroy actions and cascades are removed. Restrictive foreign keys continue to protect immutable references. Draft schema editing retains its own required removal actions.

## Risks / Trade-offs

- **[More rows and joins than JSONB]** -> Index record, field, ordinal, latest-revision, and import-status paths; benchmark representative imports before adding caches.
- **[Typed-child invariant crosses tables]** -> Use one deferred constraint trigger plus Ash transactional construction and integration tests.
- **[Derived import counts cost queries]** -> Use filtered aggregate queries over an index on import and outcome; add a projection only after measured need.
- **[Maintenance is deferred]** -> Expired data and staging accumulate; abandoned imports retain their keys; terminal jobs can strand pending rows. Restore `restore-operator-bootstrap-and-maintenance` before unattended persistent operation.
- **[An asset worker stops after claiming external work]** -> Bound the asset-local claim, permit atomic replacement after expiry, and fence stale post-I/O transitions by claim identity without introducing a generic recovery domain.
- **[Abandoned open imports retain normalized staging]** -> Apply a fixed server-calculated expiry to reject further writes; retain the import and staging until the future maintenance change restores cleanup.
- **[Storage provider remains unselected]** -> Keep the adapter narrow, ship deterministic test behavior, and fail clearly when development or production storage is absent.
- **[Record envelope appears abstract for flat data]** -> Keep its public API concrete and typed; the structure preserves the approved additive path to repeated and nested values.

## Migration Plan

1. Apply and verify `add-api-authentication`, including its Oban dependency and jobs table.
2. Generate the Assets and Datasets Ash domains and resource skeletons, then refine attributes, actions, policies, relationships, and GraphQL exposure.
3. Generate and review AshPostgres snapshots and migrations for schemas, exact record types, stable items, revisions, typed values, asset lifecycle, and simplified import rows.
4. Add the storage behavior, the shared in-memory adapter, asset lifecycle actions, verification worker.
5. Add schema publication, normalized record construction, revision fingerprinting, and immutable item revision actions.
6. Add import open, append, finalize with atomic row-job insertion, idempotent row processing and derived progress queries.
7. Run focused policy, resource, adapter, worker, concurrency, migration, and GraphQL tests; then run `mise run openspec.validate` and `mise run verify` from a clean migrated database.

Rollback before product data exists removes the new domains and tables through generated down migrations. After real assets or revisions exist, rollback requires an explicit product-data export or migration and must not silently discard immutable content or provenance.

## Resource-local generic actions and native operations

The six draft-edit generic actions and the permission predicate keep their small `run` callbacks in their resources. These are generic action implementations, not anonymous changes or validations. Draft editing retains the shared schema transaction/lock before invoking ordinary Ash create/update/destroy actions through code interfaces. The permission predicate delegates to the built-in `exists` aggregate. A plain changeset filter or `get_and_lock_for_update` on a child would not serialize edits against publication of its parent schema.

The future-issuance session check uses built-in `compare`, which supports atomic validation. The maximum lifetime check stays module-backed because it compares two fields against runtime configuration; it has no atomic callback today, but remains able to implement atomic or batch behavior later. No anonymous changes/validations or `require_atomic? false` are introduced. Underlying record-type/field update and destroy actions and session revocation retain their atomic capability.

Schema numbering uses a filtered `max` aggregate under the dataset lock. Asset-reference validation counts matching ready assets within the requested organization against the deduplicated input IDs. Native aggregate query options avoid constructing manual queries; there is no extra domain wrapper solely for a one-use aggregate. UUID bytes use `Ecto.UUID.dump!`; fingerprint framing uses `IO.iodata_length` and preserves nested iodata and the exact version-one encoding.

## Conditional updates and necessary reads

Starting asset publication and releasing an unpublished claim use code-interface updates filtered by asset/organization identity, pending state, and claim identity. Publication additionally requires an unexpired claim. These calls require the atomic strategy: eligibility is evaluated in the update instead of a separate locked read. An unmatched publication update becomes `stale_asset_claim`; release remains best-effort after missing staging. Initial claim acquisition and terminal content reconciliation retain their existing locks and decisions. Storage I/O stays outside database transactions.

Schema publication keeps the required parent-schema transaction and lock, filters its update with an `exists` condition for the requested root record type, and sets its publication timestamp through an atomic change. No matching root remains `invalid_schema`. The composite foreign key continues to protect same-schema root ownership independently. Revision creation locks existing items in the first lookup; insertion already locks newly created items until commit. Competing first inserts retain the uniqueness-conflict retry.

Read authorization still uses the shared organization-capability check. A correlated permission filter can compile into the protected SQL query, but changes forbidden reads to empty/not-found results. Strict checking preserves the current errors by retaining separate permission evaluation; adding both would add work rather than simplify it. No authorization-response contract is changed by this pass, and generic actions continue to require their explicit permission check.

## Prepared reads and bounded value batches

Revision writes and import append share a published-schema read action with explicit organization, dataset, and schema arguments and a built-in preparation loading the root's field definitions. Asset access resolves the ready record directly using the existing reverse duplicate relationship; caller authorization and `asset_not_ready` remain unchanged. Import conflict detection reads row-key, source-position, and non-null external-key matches in one scoped query after obtaining the import lock. Existing unique indexes bound matches to three records. Matching row-key retries win first, then row-key/source-position conflicts, then external-key conflicts. Row-count checks remain after locking. Finalization selects only pending row IDs while retaining scheduling order and transactional job insertion.

Record construction bulk-creates value parents with sorted returned records to preserve correspondence with normalized occurrences, then groups children by their six value families for bulk insertion. Every batch raises on errors inside the existing record transaction; no partial graph can commit, and the deferred typed-child constraint remains the independent final guard. This adds no resources, new change modules, Reactor workflows, combination queries, or public API fields.

Import append and the schema-edit boundary start their transaction through the locked parent resource. All participating resources use `QuickTrain.Repo`, so listing the entire record graph or passing additional resource lists does not add transaction coverage. Parent locks and post-lock checks remain unchanged. Asset finalization converts already-allowlisted failure atoms with `Atom.to_string/1`, and the import worker returns the domain action's success/error tuple directly, as supported by Oban.

## Import processing performance

Candidate loading reuses the field definitions already loaded with the published schema. It loads value occurrences, groups them by their actual value families, and loads only those typed relationships through Ash. It does not refetch field definitions or query absent families. Fingerprint encoding, organization/schema scope, immutable candidate reuse, and row/item locks remain unchanged. Bulk job scheduling retains complete-set rollback and ordinary Oban retries; a failure after an earlier batch insert rolls back both jobs and sealing.

## Exact text, typed-value authorization, and GraphQL work limits

Text content uses Ash string constraints `trim?: false` and `allow_empty?: true` at both import input and typed persistence. Whitespace and empty strings are content, so fingerprints and reloaded values agree. Existing lost whitespace cannot be recovered from stored content; this correction applies to new writes and does not rewrite immutable history.

All six typed-value resources use Ash policy authorization. Their primary reads require the corresponding already-authorized DatasetValue relationship; direct reads and internal writes fail closed unless trusted construction explicitly bypasses authorization.

Both GraphQL HTTP routes enable Absinthe complexity analysis with a maximum of 10,000. Dataset root collections and nested Relay collections use AshGraphql's supported complexity callbacks, sharing one function in the Datasets domain. Cost is one plus page size times child complexity (at least one per row). Omitted or null page sizes are conservatively charged at 100, the maximum exposed page size, instead of assuming one row. Negative page sizes receive a nonnegative cost and remain subject to normal pagination validation. This preserves useful nested reads while bounding total query work; callers with large selections must request smaller pages. No custom execution phase or new module is introduced.
