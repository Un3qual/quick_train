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

`Asset` contains organization ownership, lifecycle state, canonical lowercase hexadecimal SHA-256, byte size, media type, optional image dimensions, internal staging and sealed keys, staging expiry, cleanup completion, the minimal bounded operation-claim facts, and timestamps. Ready assets are immutable. A partial unique identity on organization and content hash applies only to ready assets so a failed upload does not permanently reserve the identity.

Registration rejects a declared byte size above a finite positive configured limit before returning access to a unique writable staging object. Implementation selects, tests, and documents safe defaults using representative asset sizes and image metadata rather than freezing unvalidated product limits in this design. Every staging access path enforces the declared byte-size cap through provider-native or adapter-controlled behavior before returning upload access; if the configured adapter cannot enforce it, registration fails closed instead of adding an uncapped fallback path. Finalization rechecks pinned staging and canonical-object sizes as defense in depth before reading content, parses image headers with bounded reads, rejects excessive dimensions or pixel counts before full decode, and never relies on decompression to discover limits.

One idempotent adapter operation pins a staged version or fences further writes, computes and validates its hash, size, safely detected media type, and bounded image facts, and only then conditionally publishes exactly those verified bytes at the organization-and-SHA-256 canonical immutable key. It reverifies the published canonical object before returning success. A conditional create or equivalent compare-and-converge operation ensures concurrent identical content resolves the same sealed location; an existing canonical object must be reverified against the exact pinned bytes before reuse. Mismatched staging bytes never create or occupy the declared canonical key. A per-registration sealed copy or an unpinned verify-then-copy sequence is invalid.

Finalization verifies hash, size, safely detected media type, and image dimensions from pinned staging before canonical publication and from the sealed object afterward. Active formats such as HTML, XHTML, and SVG are rejected even under a benign declaration. Concurrent identical finalizations converge on one canonical ready asset and one canonical sealed object only when size and media type also match; the losing matching registration becomes `duplicate_content`, points to the canonical asset for resolution, owns no sealed copy, and leaves only its redundant staging object cleanup eligible. Cross-organization content never shares authorization or sealed locations.

`QuickTrain.Assets.Storage` provides staging access, verify-and-seal, cleanup, and short-lived reads. Reads target only sealed objects. Returned descriptors use encrypted transport and no-store/no-referrer handling. Adapter consumers do not automatically forward credential-bearing requests across redirects: they validate each next destination before issuing it and reject insecure or unapproved destinations without disclosing credentials. This is an implementation choice that enforces the credential-safety requirement without making redirect mechanics part of the public capability contract.

A periodic responsibility-named cleanup worker scans expired rows whose `staging_cleaned_at` is null. Before storage I/O, a short transactional Ash action establishes a bounded durable operation claim only after rechecking lifecycle and expiry against the same serialized asset boundary used by finalization. Finalization and cleanup claims are mutually exclusive while live; a retry may resume its claim, and an expired abandoned claim may be atomically replaced. Every post-I/O transition compares the current claim identity so an expired or superseded worker cannot commit stale lifecycle facts. Finalization rechecks its live claim immediately before canonical publication, and each publication uses a finite adapter deadline plus a provider in-flight publication window bounded relative to that claim's expiry. After obtaining a current claim, either path first probes the declared canonical key when an earlier claimant could have published it. Matching content is boundedly reverified and atomically adopted as ready or resolved against an existing ready asset as duplicate content. If cleanup replaces an expired finalization claim, an absent canonical key remains provisional until the prior claim's publication window ends; cleanup then probes again before it may record absence. A present object that cannot be verified leaves the operation retryable, and cleanup cannot record completion while any canonical publication remains unaccounted for. This is one asset-local claim and one recovery branch in the existing lifecycle, not a generic lease or recovery subsystem; its exact minimal representation remains an implementation detail.

External adapter calls occur after the claim commits rather than while holding a database transaction open. Cleanup may retire a staging identity only after canonical publication has been reconciled and all issued upload descriptors have expired and the provider's bounded in-flight write window has elapsed, or by first irrevocably fencing further writes. It records completion only after further writes are impossible and deletion or absence is confirmed, so a late upload cannot recreate a staging object that has left the indexed scan. Completed rows leave that scan, and sealed read objects are never deleted.

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

`Dataset` is a stable organization-owned container. A schema version begins as draft and becomes immutable when published. Every record-type or field edit and publication locks the same schema-version row and rechecks its state, preventing a draft edit from committing after publication.

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

One responsibility-owned fingerprint module uses a versioned domain-separated length-prefixed encoding. Revision fingerprints include schema and root-type identities, then occurrences ordered by field identity and ordinal. Canonical typed bytes use validated UTF-8 text, minimal signed integers, normalized non-exponent decimals without insignificant zeroes or negative zero, one-byte booleans, UTC Unix microseconds, and immutable asset UUIDs. Equivalent field order, decimal scale, and time-zone offsets converge; actual type or value changes diverge.

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

An authorized manager opens an import against one dataset and published same-dataset schema, appends bounded flat rows, and finalizes it. Batch identity is unique by organization, dataset, and caller idempotency key. Matching opens return one import; changed immutable parameters conflict.

The GraphQL append action accepts one flat row per call. Finite positive configured limits bound accepted rows per import, field entries per row, total scalar bytes per row, individual text bytes, and request bytes. Implementation selects, tests, and documents safe defaults from representative imports rather than freezing unvalidated product limits in this design. The fixed input type rejects arbitrary nesting and unsupported structures. Every request, count, and byte limit is checked before canonicalization, sorting, hashing, candidate construction, or row-identity reservation.

After structural acceptance, append computes a versioned fingerprint from the schema identity, row key, external-key presence marker and length-prefixed persisted UTF-8 value when present, source position, and canonical accepted field entries. It preserves domain-invalid keys, selectors, duplicates, and scalar values without needing a total encoding for every possible malformed request tree. Equivalent field order, decimal scale, and UTC offsets converge; a changed non-null external key diverges.

Each accepted row stores its row key, source position, optional external key, fingerprint, and outcome. A valid row immediately creates an immutable normalized candidate graph; a domain-invalid row stores a terminal sanitized failure and no partial graph. Import plus row key and import plus source position are unique. Import plus non-null external key accepts only one row; competing rows fail before persistence. A keyless valid row uses its import-row UUID as its target item UUID.

Append and finalization lock the same import. An import persists only `open` or `sealed` phase plus immutable `open_expires_at`. First finalization seals the row set and inserts the complete unique row-job set in the same transaction. A periodic cleanup worker deletes only expired still-open imports after locking and rechecking them; sealed provenance is never deleted.

First finalization atomically seals the import and inserts one unique bounded-retry row job for each pending row. A failure to insert that complete bounded job set rolls back sealing, so there is no separate fan-out job that can strand rows after partial enqueue. A row job locks its row, skips terminal outcomes, and atomically commits item revision and terminal outcome. Failure before commit leaves the row pending for ordinary Oban retry. Failure after commit but before job acknowledgement is safe because the retry observes the terminal row. When no retry remains, the row must automatically receive a sanitized terminal failure so the import cannot remain pending indefinitely.

Implementation first uses the simplest supported Oban worker or job-lifecycle mechanism that can prove this terminal outcome, without adding a periodic scanner, pruning coordination, a custom processing scheduler, persisted `processing` state, lease, row attempt counter, attempt fence, or per-attempt recovery job. If the selected stable Oban release cannot guarantee terminalization across its documented failure modes, implementation pauses and updates this design with that evidence before adding reconciliation machinery.

Batch counts and lifecycle are query calculations over indexed rows, not mutable snapshots. The import query derives total, pending, succeeded, unchanged, and failed counts. A sealed import is pending while any row is pending; otherwise it is completed, failed, or partially failed from terminal outcomes. This removes parent-row serialization from independent row completion.

Source-file adapters remain later additions. A future CSV or archive importer can register its source as an Asset and call the same row actions without creating another persistence model.

### 7. Depend on the authenticated actor boundary

`add-api-authentication` is implemented first. This change adds exact capability keys `assets.read`, `assets.manage`, `datasets.read`, `datasets.manage`, and `dataset_imports.manage` plus a product-owned idempotent action for granting them to a selected existing organization manager. There is no shared bootstrap manifest or wildcard grant. Each product action derives its organization from the target resource or explicit relationship before the shared check requires an active user, active organization, active membership, and matching capability. Internal jobs advance only the immutable organization, dataset, schema, asset, or import scope accepted by an authorized caller; they do not grant read access or broaden scope.

No product content is public. Cross-organization failures do not disclose whether a dataset, schema, import, item, revision, or asset exists.

### 8. Expose deliberate GraphQL lifecycle actions

Public operations cover asset registration, finalization and authorized access; dataset and draft-schema lifecycle; import open, append, finalize and inspect; and paginated typed reads. There are no generic mutations for ready asset content, published schemas, item revisions, records, or typed values.

Stable error codes include `forbidden`, `invalid_schema`, `invalid_value`, `asset_not_ready`, `asset_identity_conflict`, `idempotency_conflict`, `import_not_open`, and `import_expired`.

### 9. Lock the authority row for related-data correctness

Schema edits and publication lock the schema version. Revision creation locks the stable item. Append, finalization, and open-import cleanup lock the import. Row processing locks the import row and then the target item only for its terminal transaction. Asset finalization and cleanup lock the asset before changing lifecycle facts.

Ash actions, `Ash.DataLayer.transaction/5`, atomic changes, and row-locking queries are the default. Composite constraints and the typed-child trigger are narrow database backstops generated through AshPostgres; application code does not bypass Ash with direct Ecto writes.

### 10. Use responsibility-specific durable jobs

This change reuses the stable pinned Oban dependency established by the authentication prerequisite. Workers are responsibility-named for asset verification, asset staging cleanup, import-row processing, and expired-open-import cleanup. Jobs carry only resource identities, not dataset content. Job uniqueness prevents duplicate row processing and overlapping periodic cleanup, while application actions remain independently idempotent.

QuickTrain does not recreate generic Operations, Integrations, Audit, or DurableDelivery domains.

## Risks / Trade-offs

- **[More rows and joins than JSONB]** -> Index record, field, ordinal, latest-revision, and import-status paths; benchmark representative imports before adding caches.
- **[Typed-child invariant crosses tables]** -> Use one deferred constraint trigger plus Ash transactional construction and integration tests.
- **[Derived import counts cost queries]** -> Use filtered aggregate queries over an index on import and outcome; add a projection only after measured need.
- **[A repeatedly failing row exhausts Oban retry policy]** -> Require a sanitized terminal outcome through the simplest supported Oban lifecycle mechanism; add reconciliation only after implementation evidence and an explicit design update.
- **[An asset worker stops after claiming external work]** -> Bound the asset-local claim, permit atomic replacement after expiry, and fence stale post-I/O transitions by claim identity without introducing a generic recovery domain.
- **[Abandoned open imports retain normalized staging]** -> Apply a fixed server-calculated expiry and periodic deletion of only still-open imports.
- **[Storage provider remains unselected]** -> Keep the adapter narrow, ship deterministic development and test behavior, and fail clearly when production storage is absent.
- **[Record envelope appears abstract for flat data]** -> Keep its public API concrete and typed; the structure preserves the approved additive path to repeated and nested values.

## Migration Plan

1. Apply and verify `add-api-authentication`, including its Oban dependency and jobs table.
2. Generate the Assets and Datasets Ash domains and resource skeletons, then refine attributes, actions, policies, relationships, and GraphQL exposure.
3. Generate and review AshPostgres snapshots and migrations for schemas, exact record types, stable items, revisions, typed values, asset lifecycle, and simplified import rows.
4. Add the storage behavior, deterministic adapters, asset lifecycle actions, verification worker, and staging cleanup.
5. Add schema publication, normalized record construction, revision fingerprinting, and immutable item revision actions.
6. Add import open, append, finalize with atomic row-job insertion, cleanup, idempotent row processing, terminal retry-exhaustion handling, and derived progress queries.
7. Run focused policy, resource, adapter, worker, concurrency, migration, and GraphQL tests; then run `mise run openspec.validate` and `mise run verify` from a clean migrated database.

Rollback before product data exists removes the new domains and tables through generated down migrations. After real assets or revisions exist, rollback requires an explicit product-data export or migration and must not silently discard immutable content or provenance.
