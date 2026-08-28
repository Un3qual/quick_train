## Context

See `proposal.md` for motivation and the four delta specs for behavioral requirements.

QuickTrain currently contains backend-only account, organization, authorization, enterprise identity, and GraphQL foundations. It has no product datasets, forms, projects, tasks, finance, or reputation resources. The current session resource can hold a hashed token, but the GraphQL pipeline does not yet resolve an authenticated actor and several foundation domains expose policy-disabled GraphQL operations. Product data must not inherit that posture.

This change is the first of five approved product changes:

1. `add-normalized-datasets-and-assets`
2. `add-versioned-forms`
3. `add-project-task-collection`
4. `add-marketplace-finance`
5. `add-worker-reputation`

The implementation scope of this change is only the first item. The final appendix is a durable record of approved cross-change decisions, not an expansion of this change's requirements or tasks.

## Goals / Non-Goals

**Goals:**

- Add organization-owned asset and dataset domains using Ash resources and AshPostgres.
- Normalize dataset content into schemas, record types, field definitions, item revisions, records, value occurrences, and typed value tables.
- Keep source content immutable and historically unambiguous.
- Support idempotent programmatic import batches without persisting opaque item payloads.
- Establish an additive path to repeated and nested record values without implementing arbitrary nested input now.
- Establish authenticated, fail-closed GraphQL actions before exposing product content.
- Use responsibility-specific durable jobs for login-state cleanup, asset verification, staging cleanup, import processing, lease recovery, and abandoned-open-import cleanup.

**Non-Goals:**

- Implement Forms, Projects, Tasks, responses, review, exports, Finance, or Reputation.
- Choose a production object-storage vendor.
- Add frontend code or external form integration.
- Store dataset content or import row payloads in JSONB.
- Create customer-specific PostgreSQL tables.
- Implement nested record values, item graphs, or arbitrary recursive input in this change.
- Implement audio/video annotation ranges or any task answer representation.

## Decisions

### 1. Add `QuickTrain.Assets` and `QuickTrain.Datasets` as separate Ash domains

`QuickTrain.Assets` owns immutable binary-content identity and authorized storage access. `QuickTrain.Datasets` owns customer schemas and normalized logical content. Datasets depend on Assets for asset-valued fields; Assets do not depend on Datasets.

The top-level `QuickTrain` boundary exports both domains and the asset storage behavior. Product resources use `AshGraphql.Resource`, and each domain uses `AshGraphql.Domain` with authorization enabled.

Alternatives rejected:

- One generic content domain would mix binary storage lifecycle with dataset schema and revision lifecycle.
- Placing assets inside Datasets would create an unnatural dependency when later raster-mask answers also need assets.
- A generic CRUD/service layer would obscure the product actions and authorization boundary.

### 2. Use immutable, content-addressed asset metadata with a provider-neutral adapter

`Asset` contains organization ownership, lifecycle state, a SHA-256 content hash represented everywhere as 64 lowercase hexadecimal characters, byte size, media type, optional image width and height, internal staging and sealed storage keys, a staging expiry, a nullable staging-cleaned timestamp, and timestamps. Ready assets are immutable. A partial unique identity on organization and content hash applies only to ready assets, so a failed upload does not prevent a later correct registration. Registration returns an upload descriptor for a unique staging object. Finalization uses one idempotent adapter operation that pins a staging version or conditionally fences further writes, seals exactly those bytes at a content-addressed key or immutable provider version, and returns the sealed identity plus its verified facts. If a provider cannot pin the staged version, the adapter must irrevocably fence staging writes before sealing and then verify the sealed object. The database records the sealed identity and moves the asset to ready only when the SHA-256 hash, size, actual media type, and image facts were computed from that same immutable sealed object; a separate verify-then-copy sequence is not valid. Registration, adapter results, deduplication, and storage-key construction all validate and use the same canonical hash representation.

The first-release supported-media policy rejects active document formats, including HTML, XHTML, and SVG. Finalization identifies or safely sniffs the sealed bytes rather than trusting the registered media type, rejects a declared/actual media-type mismatch, and never makes active content ready under a benign declaration. This preserves safe raster-image use without requiring a production storage vendor or browser-execution policy in this change.

If concurrent finalizations produce the same ready identity, the uniqueness conflict resolves to the canonical ready asset only when its byte size and media type exactly match the new registration; otherwise the caller receives an asset-identity conflict. The losing matching pending asset records a sanitized `duplicate_content` terminal state and its redundant object is eligible for cleanup. Registering content that is already ready likewise returns the canonical asset without creating another upload only after exact metadata agreement. Cross-organization content never shares authorization even if the bytes match.

`QuickTrain.Assets.Storage` is a narrow behavior for staging upload access, verification, idempotent promotion or sealing, redundant-object cleanup, expired-staging cleanup, and short-lived read access. A responsibility-named cleanup worker removes staging objects after their descriptor/registration expiry plus a fixed safety grace period when the asset is still pending, failed, in the `duplicate_content` terminal state, or already sealed; it never deletes a sealed read object. The worker is registered with Oban's supported periodic scheduler at a fixed interval, scans the indexed boundary where staging expiry is old and `staging_cleaned_at` is null, and uses job uniqueness to prevent overlapping scheduled runs while the cleanup operation itself remains idempotent. After the adapter confirms deletion or absence, the cleanup action locks the asset and records `staging_cleaned_at`; a failed database update may repeat the idempotent provider delete, but a completed row is never selected again. Cleanup therefore occurs even when a client registers and uploads content but never calls finalization without rescanning all historical assets forever. Development and tests use a deterministic filesystem/test adapter. Production configuration must select an adapter; this change does not choose S3 or another vendor. Reads only target sealed keys, never writable staging keys, so an unexpired upload descriptor cannot change ready content.

Storage credentials and persistent object locations are never GraphQL fields. GraphQL returns only short-lived adapter-produced access descriptors after an Ash authorization action succeeds. Every credential-bearing descriptor uses authenticated encrypted transport and carries no-store/no-referrer handling so credentials are not propagated through caches or referrer metadata. Redirects are not followed automatically: the adapter consumer validates each target's secure scheme and adapter-approved destination before issuing the next request and forwards no credential-bearing header or query parameter to a rejected target.

Alternatives rejected:

- Storing bytes in PostgreSQL would inflate backups and couple large-object delivery to the transactional database.
- Storing public URLs would bypass authorization and make asset relocation unsafe.
- Mutable object keys would invalidate spatial answers and historical item revisions later.

### 3. Model dataset schemas explicitly and publish immutable versions

Core resources:

```text
Dataset
└── DatasetSchemaVersion
    └── DatasetRecordType
        └── DatasetFieldDefinition
```

`Dataset` is a stable organization-owned container. A schema version begins as draft and becomes immutable when published. Every record-type or field create, update, or delete action locks its parent schema-version row and rechecks that it is still draft inside the write transaction. Publication takes the same lock before validating the complete graph and changing state, so an edit that began against a draft cannot commit after publication. A version designates exactly one of its own record types as its root in the first release, backed by same-schema relational constraints. Field definitions have a stable key, display name, value family, required flag, and cardinality. Field keys are unique within a record type.

Initial value families are text, integer, decimal, boolean, UTC date-time, and asset. The only first-release cardinality is `single`; required fields contain exactly one occurrence and optional fields contain zero or one. The canonical record-construction action rejects a second occurrence atomically. Cardinality and occurrence ordinals are persisted now so repeated scalar values can be enabled without replacing existing tables or rewriting existing records.

Alternatives rejected:

- Inferring a schema independently for every row makes validation and reusable form bindings unreliable.
- PostgreSQL enums for customer field names or customer-specific tables would require migrations for customer data.
- An untyped field catalog would move type failures from import time to task execution.

### 4. Give every item a stable identity and immutable revisions

```text
DatasetItem
└── DatasetItemRevision
    └── root DatasetRecord
        └── DatasetValue
            └── exactly one typed value child
```

`DatasetItem` is identified by a UUID and, when supplied, a customer external key unique within its dataset. `DatasetItemRevision` pins a published schema version from that same dataset, an immutable root record whose type is exactly that schema version's designated root type, a monotonically increasing revision number, and a content fingerprint computed from the schema-version identity plus the normalized record values. Dataset/schema and schema/root-type consistency are enforced in public and private Ash actions and backed by composite database identities and foreign keys on the dataset, schema version, record type, item, revision, and import relationships.

One responsibility-owned fingerprint module supplies two versioned, domain-separated encodings. Revision content uses an unambiguous length-prefixed normalized record stream that includes the schema-version and root-record-type UUID bytes and orders occurrences by field-definition UUID bytes and then ordinal, independent of caller field order. Each occurrence includes its field UUID, value-family tag, ordinal, and canonical typed bytes: exact validated UTF-8 for text; minimal signed base-10 for integers; non-exponent decimal form with insignificant trailing zeroes and negative zero removed; one byte for booleans; signed UTC Unix microseconds for date-times; and immutable asset UUID bytes for assets. Absent optional values emit no occurrence.

Import-row request identity is computed before schema validation from the complete bounded append input, so accepted invalid rows are fingerprintable without retaining an opaque payload. Its separately tagged length-prefixed stream includes the schema/root identities, row key, external-key null/present marker, source position, every other immutable parameter, every supplied field key and value-family selector, omitted-versus-null markers, duplicate occurrences, and unsupported nested structure. Object members sort by exact UTF-8 key bytes. Top-level field occurrences sort by exact UTF-8 field-key bytes, then selector tag, then their complete canonical value bytes while retaining multiplicity; nested list order is preserved. Syntactically valid supported scalars use the same canonical family bytes as revision content, so equivalent field order, decimal scale, UTC offset, or occurrence order converges; malformed or unsupported values use a total type-tagged recursive representation that preserves their complete parsed scalar kind, bytes, and structure, so any changed invalid input diverges. No raw request tree is persisted after the fingerprint is computed. Both encodings use SHA-256 represented as 64 lowercase hexadecimal characters.

Corrections create new revisions. Existing projects will later pin exact item revisions, so source text, images, boxes, masks, polygons, and spans cannot change underneath historical responses.

For a supplied external key, revision creation first performs an atomic get-or-create by the dataset-scoped item identity and reloads the winning row after a uniqueness conflict. It then locks that authoritative item row before comparing the latest schema-aware fingerprint and assigning the next revision number. Identical values validated under a different published schema therefore create a new historical revision rather than reusing a revision pinned to the wrong schema. This covers both first-revision races and later revision races; database identities backstop external-key and revision-number uniqueness.

### 5. Use a typed record envelope rather than JSONB or a generic tree

`DatasetRecord` is an immutable instance of exactly one `DatasetRecordType` from its pinned schema version that may be referenced first as a validated import-row candidate and later as an accepted item-revision root. A first-release revision candidate must use that schema version's designated root type. It is not an opaque import payload. `DatasetValue` identifies one field occurrence with a field definition from its owning record's exact record type and an ordinal. Typed one-to-one resources contain the value:

- `DatasetTextValue`
- `DatasetIntegerValue`
- `DatasetDecimalValue`
- `DatasetBooleanValue`
- `DatasetDateTimeValue`
- `DatasetAssetValue`

The root/value split is deliberate. Repeated values later require only allowing additional ordinals. Nested records later add a record-valued typed child pointing to another `DatasetRecord`; existing root, occurrence, and scalar rows remain unchanged.

Exactly one typed child must exist and match the field definition. Ash creation actions build the record graph transactionally and resolve input keys only within the record's exact type, never across all types in the schema. Composite identities and foreign keys repeat the necessary record-type and schema-version keys so PostgreSQL rejects a value whose field belongs to a sibling type and rejects a revision whose record is not the schema's designated root. Because an ordinary PostgreSQL check constraint cannot count subtype rows, a deferred constraint trigger is an approved narrow database-boundary exception to reject missing, duplicate, or mismatched typed children at commit. The trigger is generated through the AshPostgres migration and covered by integration tests; application code does not use direct Ecto writes.

Alternatives rejected:

- Nullable scalar columns directly on each item make repeated and nested fields awkward.
- JSONB preserves import shape but loses relational typing, foreign keys, and efficient value-level validation.
- A fully generic self-referential EAV tree is flexible but weakens understandable type and ownership invariants.
- Type-specific tables without a stable value occurrence make generic form bindings and future record values harder to reference.

### 6. Process programmatic imports as normalized rows without staging opaque payloads

Core resources:

```text
DatasetImport
└── DatasetImportRow
```

An authorized manager opens an import against one dataset and a published schema version belonging to that dataset, submits normalized rows in bounded GraphQL batches, and finalizes the import. The append action creates every `DatasetImportRow` transactionally. Valid input is constructed immediately as an immutable normalized `DatasetRecord` and typed value graph referenced by the row as its staged candidate; invalid input leaves no partial record graph and stores a terminal failed row outcome. A product-specific durable job consumes only row and record identities, never content in Oban arguments. On success, the resulting immutable item revision references the already validated candidate record.

Batch identity is unique on organization, dataset, and caller-supplied idempotency key. The request fingerprint includes the pinned schema version and other immutable open parameters. Opening a batch uses an atomic create-or-return operation: concurrent matching requests return the same batch, while a changed request under the same identity fails with `idempotency_conflict`.

Every appended row supplies and persists a caller-stable row key unique within the import, an optional customer external key, a unique source position, and a fingerprint over its complete pre-validation input plus all immutable row parameters. Append computes that fingerprint before validation, then applies the same atomic create-or-return rule. A matching retry returns the already accepted row without reconstructing or reprocessing it; reuse of the row key or source position for any changed valid or invalid input fails with `idempotency_conflict`. A partial database identity on import and non-null external key reserves each named target item at most once in a batch. The first committed append wins that identity and every competing duplicate is rejected with `duplicate_external_key`, so worker scheduling cannot choose which of two rows becomes the final value. For a valid row without an external key, the persisted `DatasetImportRow` UUID is also its target `DatasetItem` UUID. The worker creates or locks that exact item in the same atomic revision/outcome transaction, so a lost or reclaimed attempt cannot create a second keyless item and no empty item is created merely by appending an ultimately abandoned row.

Rows commit independently so a large batch can finish partially. Failed `DatasetImportRow` outcomes remain stored even though no invalid item revision or partial record graph is persisted, allowing lifecycle counts and paginated provenance to remain accurate. A duplicate external key is rejected before it becomes an accepted import row, so it cannot conflict with the rule that every accepted invalid row retains a terminal outcome.

Appending and finalizing serialize on the same locked `DatasetImport` row. Append rechecks that the locked import is `open` and has not reached `open_expires_at` before it persists a row; the first finalization applies the same checks, then atomically changes the persisted phase to `sealed` while inserting one import-identity-unique processing job. An expired still-open import rejects both actions with `import_expired` and remains eligible for cleanup. An authorized identical finalization retry against an already sealed import returns that current import without reapplying the old open expiry or inserting another job; concurrent attempts serialize to the same result. The worker therefore sees a sealed row set, an append that loses the race is rejected with `import_not_open`, and a lost finalization response can be retried safely even after the original open-expiry timestamp.

Every import receives a server-calculated immutable `open_expires_at` at creation. A uniquely scheduled responsibility-named cleanup worker scans the indexed expired-and-open boundary, locks each candidate import, and deletes only a still-open expired import together with its unprocessed rows and candidate record graphs. Finalization takes the same lock. A finalization that acquired the lock and verified the import before expiry may seal it while cleanup waits, after which cleanup skips it; if finalization first acquires the lock after expiry, it returns `import_expired` and leaves the import open for cleanup. Sealed imports and their provenance are never deleted. The fixed lifetime is not extended by append traffic, which bounds abandoned relational staging and eventually releases the idempotency identity even when the initiating user loses access.

An import persists only its `open` or `sealed` phase. For a sealed import, the public lifecycle is a read-time calculation using the database clock and current row facts: any unexpired processing lease yields `processing`; otherwise any pending row or expired processing lease yields `pending`; otherwise zero rows or terminal rows with no failures yield `completed`; terminal rows that all failed yield `failed`; and any other terminal mix of failed with succeeded or unchanged rows yields `partially_failed`. This prevents a delayed recovery job from leaving an expired lease visibly stuck in a persisted `processing` lifecycle. Counters are persisted exactly: `row_count` is the total number of persisted `DatasetImportRow` records, while `pending`, `processing`, `succeeded`, `unchanged`, and `failed` are mutually exclusive outcome counts whose sum equals `row_count`; `failed` includes append-validation and processing failures. Every append, claim, reclaim, and terminal outcome transaction locks the parent import before the affected row, recomputes the exact counters from rows while holding that serialization lock, and persists the counter snapshot before commit. This common import-then-row lock order prevents simultaneous workers from losing counter updates. A processing row remains in the processing outcome count even when its expired lease makes the calculated lifecycle `pending`. A competing `duplicate_external_key` append is rejected before row persistence, so it changes neither `row_count` nor `failed`.

Workers claim pending rows or processing rows whose lease has expired, recording `processing_started_at`, `lease_expires_at`, and an incremented attempt count under the import-then-row lock order. The returned attempt number is a fencing token: a terminal update succeeds only when the row is still processing under that exact attempt. The same claim transaction inserts one unique row-and-attempt recovery job scheduled for that lease expiry. That wake-up rechecks the row and exits if the attempt is terminal or no longer current; otherwise it reclaims the expired lease even when the original worker is still alive or never reached an exit path. A retry skips terminal rows and active leases but safely reclaims stale processing rows; a stalled older attempt cannot overwrite a newer attempt's outcome after resuming. Rows targeting the same stable item serialize on its row lock after the external-key atomic get-or-create step or by using the row-derived UUID for a keyless item.

Authorization is checked when a caller opens, appends to, finalizes, or inspects an import and includes the target organization's active status. Successful finalization creates a durable organization-owned command pinned to the already authorized organization, dataset, and schema version. The internal worker advances only that immutable scope through private actions; it does not reauthorize the initiating user's mutable membership or the organization's later status on every attempt. Later account, membership, capability, or organization deactivation blocks every new caller action and inspection but does not retroactively cancel accepted work. This treats organization deactivation as an access suspension rather than an implicit destructive cancellation of committed imports.

Source-file format adapters are later additions. A future CSV or archive import can register its source file as an Asset and emit the same normalized row actions; it does not require a second dataset persistence model.

### 7. Make authorization actor-aware and fail closed before exposing product data

The existing OIDC helpers and login-transaction resource do not yet complete a client authentication handshake. This change adds unauthenticated begin/exchange actions. Begin generates the state, nonce, PKCE verifier, and a separate client-bound redemption secret server-side with a cryptographically secure random generator using at least 256 bits of entropy for each value. It stores a unique collision-checked state hash, nonce hash, server-side verifier, and redemption-secret hash; returns the raw redemption secret only to the initiating client; never places that secret in the provider authorization request, callback URI, logs, or persistent state; derives an S256 challenge from a standards-compliant verifier; and rejects caller-supplied state, nonce, verifier, challenge, or redemption-secret material at begin. Callback URIs come only from trusted server configuration; begin persists the selected callback configuration identity and exact URI on the login transaction, and exchange reloads and passes that exact URI to the provider rather than accepting a caller-supplied value. Exchange requires the initiating client's redemption secret and atomically claims an unexpired login transaction only when its constant-time hash comparison succeeds, through a one-way `pending` to `exchanging` transition before any provider request may continue. A mismatch is rejected before provider exchange or session issuance.

The first release supports exactly one configured account-linking policy, `issuer_subject_only`. Missing or unknown policy configuration fails closed before login can proceed. The canonical identity is the verified OIDC issuer URI plus subject from a provider response whose signature, issuer, audience, nonce, and expiry checks passed. Before issuer-only lookup is enabled, a staged data migration maps every legacy `provider == "oidc"` identity to the one configured canonical issuer URI and aborts on missing/multiple issuer configuration or any issuer/subject or user/provider conflict; no ambiguous row is guessed or silently relinked. The migration also inventories global users without an external identity and provides a responsibility-named operator-only command, outside GraphQL, that consumes an operator-reviewed manifest mapping an exact active user UUID to the configured canonical issuer URI and exact provider subject. Each mapping locks the user and identity uniqueness boundaries, is idempotent only for the same relationship, and fails atomically on a missing/inactive user, an issuer/subject already owned by another user, or a conflicting canonical identity for the target user. The command never discovers or selects a user by email, and unmapped collisions continue to fail closed during login. An existing identity resolves only its immutable user relationship when both the identity and linked global user are active; exchange locks and rechecks both lifecycle states in the same transaction that creates the session and consumes the login transaction. Provider claim refresh may update non-identity claims but can never change lifecycle status or upsert `user_id`, so a disabled identity cannot reactivate itself during login. A new identity and user begin active and require a non-empty provider-verified email. The user display name is the first nonblank trimmed `name` or `preferred_username` claim, falling back deterministically to the normalized verified email's nonempty local part; display-name input never participates in account linking. Email is never used to link or reassign an existing user. If the matched identity or user is disabled or has an unknown status, exchange fails closed with a non-disclosing authentication error and no session. If the verified email already belongs to another user, or any issuer/subject/user identity conflicts, exchange returns `account_linking_conflict` without issuing a session.

Only the request that wins the conditional login-transaction claim may apply that policy and issue a high-entropy opaque bearer token exactly once; every concurrent or later claimant is rejected, and a failed or interrupted claimant cannot make the state reusable. Session creation and the final `consumed` transition commit together. Only the token's SHA-256 hash, expiry, method, and user relationship are authoritative for a newly issued global-account session; issued hashes are non-null and protected by a unique database identity and index for one-row hot-path lookup. Before enabling that global bearer resolver, a staged migration marks every legacy null-hash session revoked and assigns it a distinct reserved `legacy-revoked:<session-id>` value that bearer hashing cannot produce, and separately revokes every legacy session with a non-null organization relationship. New issuance never sets an organization relationship, and a database constraint permits a retained non-null legacy `organization_id` only on a revoked row. This preserves legacy audit facts without silently widening an organization-scoped credential into a global authenticator.

Every login transaction has an expiry and a retention cutoff after that expiry. A responsibility-named Accounts cleanup worker deletes consumed, expired, or abandoned transactions only after the fixed replay-rejection retention interval, never removes an unexpired pending or exchanging transaction, and treats a missing state as invalid. The worker is registered with Oban's supported periodic scheduler at a fixed interval, and uniqueness prevents overlapping scheduled cleanup jobs. This bounds storage without relying on manual invocation, reopening a consumed state, or weakening expiry checks.

The API pipeline hashes a presented bearer token, resolves a live global-account session and active global `User`, and sets that user as both the Absinthe and Ash actor. A session authenticates only the account and never grants or pins organization authority; every target organization is derived from the protected resource or explicit action relationship rather than a session field. Product actions require:

1. an active authenticated user;
2. an active target organization;
3. an active membership in that organization; and
4. the relevant explicit capability.

Initial capability keys are `assets.manage`, `datasets.manage`, `datasets.import`, and read-only equivalents where separate read delegation is useful. Resource ownership is derived from relationships, not a trusted organization header. Internal relationship loads can bypass authorization only after the public action has proven scope and only through private actions.

Because these checks deliberately make a fresh installation inaccessible to ordinary product actions, a responsibility-named operator-only Mix task bootstraps the first manager. It accepts an exact existing active user identity plus organization name and slug, then transactionally and idempotently creates or resolves the active organization, active membership, manager role assignment, and initial product-capability grants. It fails on conflicting organization or user facts, is never exposed through GraphQL, and uses the same Ash actions and validations as later authorized management flows.

The implementation removes the GraphQL `health` field, keeps operational health only at `/healthz`, restricts GraphiQL to development, and removes every existing policy-disabled foundation field, including broad user list/read/create operations, from the public GraphQL schema. Those actions may remain internal Ash APIs for tests and trusted operator workflows, but placing them behind bearer middleware is not authorization and does not make them public. The OIDC begin/exchange handshake is the only unauthenticated GraphQL behavior.

### 8. Expose deliberate GraphQL lifecycle actions

Public actions cover:

- creating and reading datasets;
- drafting and publishing schema versions;
- defining root record types and fields while the version is draft;
- registering, finalizing, and obtaining authorized access to assets;
- opening, appending normalized rows to, finalizing, and inspecting imports; and
- paginated typed reads of items and revisions.

There are no public generic update/delete actions for published schema versions, ready asset content, item revisions, records, or typed values. GraphQL errors use stable codes such as `forbidden`, `invalid_schema`, `invalid_value`, `asset_not_ready`, `asset_identity_conflict`, `idempotency_conflict`, `import_not_open`, and `import_expired`.

### 9. Use Ash transactions and row locks for related-data correctness

Publishing a schema and every draft child edit lock the same schema-version row and recheck its lifecycle state before validating or writing. Creating a revision atomically obtains the dataset-scoped item, locks it, and then compares the latest schema-aware content fingerprint and assigns the revision number. Appending, finalizing, cleaning, claiming, reclaiming, and completing import rows likewise lock the parent import first, followed by the row and then any target item needed by that short transaction, before rechecking or changing the persisted phase and counter snapshot; the lease-aware public import lifecycle remains a read-time calculation. Every typed value validates its field, cardinality, dataset, schema, and asset relationships inside the same transaction that creates the candidate record or revision. In the first release, every ready same-organization asset is compatible with an asset-family field; media-type or dimension constraints are deferred to later form bindings.

Ash actions, `Ash.DataLayer.transaction/5`, query locks, atomic changes, and `get_and_lock_for_update` are the default. Composite same-schema, exact-record-type, and designated-root-type foreign keys backstop the corresponding Ash validations. `FOR UPDATE SKIP LOCKED` is reserved for later task allocation; imports targeting a known item use ordinary row locks. Direct SQL is limited to generated constraints/triggers that AshPostgres cannot express declaratively.

### 10. Reintroduce durable jobs only for responsibility-specific asynchronous work

Oban is added at the stable GA version selected during implementation and pinned exactly while `.mise.toml`, `mix.exs`, and `mix.lock` are updated together. Its supported migration generator creates the jobs-table migration before workers are enabled. Initial workers are responsibility-named: `QuickTrain.Accounts.CleanupOidcLoginTransactionsWorker`, `QuickTrain.Assets.VerifyWorker`, `QuickTrain.Assets.CleanupStagingWorker`, `QuickTrain.Datasets.ImportWorker`, and `QuickTrain.Datasets.CleanupOpenImportsWorker`. Job insertion is idempotent and, when coupled to a state transition or processing lease, occurs transactionally with the application record. OIDC transaction cleanup, asset staging cleanup, and abandoned-open-import cleanup are configured in Oban's supported periodic scheduler rather than relying on a caller, finalization attempt, or manual run; each job's uniqueness window prevents overlapping executions while its cleanup action remains independently idempotent. Each import-row claim also schedules its own unique recovery wake-up at lease expiry, so crash recovery does not depend on a running worker reaching an exit path.

QuickTrain does not recreate generic Operations, Integrations, Audit, or DurableDelivery domains. The authoritative authentication, asset, and import resources contain their own state; jobs only advance or clean those responsibility-owned records.

## Risks / Trade-offs

- **[More rows and joins than JSONB]** → Keep GraphQL reads explicit, add indexes on record/field/ordinal and latest-item revision paths, and benchmark representative imports before optimizing.
- **[Typed-child invariant crosses tables]** → Use a deferred PostgreSQL constraint trigger plus Ash transactional construction and tests that attempt invalid direct database states.
- **[Asset provider remains unselected]** → Keep the adapter narrow, ship deterministic development/test behavior, and fail startup or asset actions clearly when production storage is not configured.
- **[Partial imports complicate client recovery]** → Give every row a terminal outcome, stable idempotency identity, normalized candidate-record reference when valid, a sealed batch boundary, and a recoverable attempt-fenced processing lease.
- **[Abandoned open imports can retain normalized staging indefinitely]** → Give every batch an immutable server-calculated open expiry and periodically delete only still-open expired imports under the same lock used by finalization, never sealed provenance.
- **[Writable staging can outlive abandoned uploads]** → Persist and index staging expiry plus a nullable cleanup-completion marker, apply a fixed cleanup grace period, and automatically scan and remove each staging object through an idempotent, uniquely scheduled responsibility-named worker without rescanning completed history.
- **[Unauthenticated login starts can accumulate state]** → Persist a retention cutoff and periodically delete expired or consumed login transactions after a fixed replay-rejection interval through an idempotent, uniquely scheduled responsibility-named worker.
- **[Row locking can serialize hot external keys]** → Atomically get or create the item, lock only the targeted stable item, and keep revision transactions short; unrelated items remain concurrent.
- **[The actor pipeline expands foundation scope]** → Implement it before product GraphQL actions, cover unauthenticated and cross-organization access, and avoid exposing broad foundation reads.
- **[Record envelope appears abstract for flat data]** → Keep its public API concrete and typed; the extra relationship buys an additive path to repeated and nested records that the product explicitly requires.

## Migration Plan

1. Add the exact stable Oban dependency, supported jobs-table migration, and configuration required for product jobs, updating `.mise.toml`, `mix.exs`, and `mix.lock` together.
2. Inventory legacy users without identities, apply only operator-reviewed exact user-to-issuer/subject mappings, migrate legacy `provider == "oidc"` identities to the one configured canonical issuer URI with conflict detection, revoke and assign reserved non-authenticating values to legacy null-hash sessions, and revoke every legacy organization-scoped session before enabling global-account bearer resolution. Then complete the OIDC-to-bearer-session handshake with server-generated state, nonce, S256 PKCE, separate client-bound redemption proof, server-pinned callbacks, deterministic display-name fallback, the `issuer_subject_only` linking policy plus active external-identity and active-user checks, periodically scheduled bounded login-transaction retention, required uniquely indexed session token hashes, the authenticated GraphQL actor pipeline, removal of policy-disabled foundation GraphQL fields, active-organization checks, capability definitions, first-manager operator bootstrap, development-only GraphiQL, and fail-closed tests before registering product domains in the schema.
3. Generate the Assets and Datasets Ash domains/resources, then deliberately refine attributes, actions, policies, relationships, identities, and GraphQL exposure.
4. Generate AshPostgres migrations and snapshots, including dataset/schema, exact-record-type, and designated-root-type composite constraints, ready-asset partial uniqueness, active-session organization-scope constraints, import idempotency, open-expiry, persisted-counter, lock-order, and lease-recovery constraints, the deferred typed-child constraint trigger, and required indexes.
5. Add the storage behavior and deterministic development/test adapter with distinct writable staging and sealed read objects.
6. Add asset lifecycle actions, the verification worker, and uniquely scheduled periodic staging cleanup.
7. Add schema publication, item revision, normalized record/value, and import actions and workers.
8. Run focused tests, `mise run openspec.validate`, and `mise run verify` from a clean migrated database.

Rollback before product data exists removes the new domains, jobs, and tables through the generated down migrations. After real assets or dataset revisions exist, rollback is an explicit product-data migration/export operation; it must not silently discard content or immutable provenance.

## Approved Cross-Change Architecture Record

This appendix preserves the approved design for later OpenSpec changes. It is non-normative for the current change and must be converted into capability specs and scoped tasks in each follow-up change. A later explicit user decision may revise it.

### A. Product domains and dependency direction

Approved product domains:

```text
QuickTrain.Assets
       │
       ▼
QuickTrain.Datasets ──┐
                      ├──▶ QuickTrain.Projects ──▶ QuickTrain.Tasks
QuickTrain.Forms ─────┘

QuickTrain.Finance and QuickTrain.Reputation integrate through named task
funding, settlement, and eligibility workflows rather than generic services.
```

- Assets own immutable content identity and storage access.
- Datasets own schemas, records, stable items, and revisions.
- Forms own reusable versioned task contracts.
- Projects bind one form version to one stable dataset cohort and configuration.
- Tasks own fetched selections, allocation, attempts, responses, review, and raw result evidence.
- Finance owns offers, reservations, ledger accounting, earnings, and payouts.
- Reputation owns global and organization-scoped rebuildable worker projections.
- Existing Accounts, Organizations, Authorization, and EnterpriseIdentity remain foundations.

Cross-domain workflows are named for their responsibility, such as `ProjectActivation`, `TaskGeneration` or selection, and work settlement. There is no generic Core, CRUD, Services, Operations, or DurableDelivery product layer.

### B. Forms are QuickTrain task contracts, not external integrations

There is no external-form import or externally hosted form flow in the approved first release. A customer imports or creates dataset content, then defines in QuickTrain how items are presented and what questions workers answer.

```text
Form
└── FormVersion
    ├── InputSlotDefinitions
    │   └── InputFieldRequirements
    ├── ordered PresentationElements
    ├── QuestionDefinitions
    ├── QuestionOptions
    └── LabelSets and Labels
```

A form version owns input slots, presentation elements, and questions together. It is editable as a draft and immutable after publication. Projects pin published versions.

The form declares typed reusable requirements instead of concrete dataset field IDs. A project maps requirements such as `candidate.body:text` to fields such as `response_text:text`. Activation validates type, cardinality, requiredness, and media compatibility and freezes the bindings.

Question renderer type is separate from answer value family. Radio, dropdown, pairwise, and image choice can share a selection representation; stars, Likert, and integer controls can share an integer representation. Static options and dynamic task-input options remain distinct relational references.

Form elements form one ordered presentation sequence with normalized subtypes for instructions, bound values, question placement, and structural headings/sections. Question-family constraints use typed resources rather than JSON configuration.

### C. Dataset content and task grouping are separate

Datasets contain atomic immutable item revisions. Forms describe required input slots and questions. A task selection can contain one or several dataset items:

```text
Single rating: subject × 1 → “Rate this response”
Pairwise:     candidate × 2 → “Which do you prefer?”
Group task:   candidate × N → ranking or other questions
```

The form and its questions are defined once. QuickTrain never creates a form or question copy for every dataset item.

### D. Projects freeze cohorts, bindings, and policies

An approved project pins:

- one organization;
- one dataset and an explicit cohort of immutable item revisions;
- one published form version;
- typed form-to-dataset bindings;
- grouping and selection configuration;
- worker audience and eligibility settings;
- automatic or manual review;
- per-question answer, skip, and escalation settings;
- coverage settings;
- and, when Finance is implemented, a rate/funding configuration.

Project lifecycle is `draft → active ⇄ paused → completed → archived`. Activation validates and freezes configuration. New dataset imports never silently enter an active project; managers explicitly enroll item revisions in a later cohort/batch.

### E. Both worker audiences and allocation modes are first-class

The global `User` remains the only account model. Organization membership is optional. Projects support `organization_members`, `external_users`, or `both` audiences without separate task or response tables.

External access initially supports open authenticated access and explicit allowlists, with future qualification/geography/reputation requirements as additive eligibility rules. Explicit blocks override positive routes. A user may qualify through membership and external eligibility simultaneously.

Work can be obtained by pool claim or direct assignment. Both routes create the same leased Attempt state machine and response model.

### F. Selection happens at fetch time; unused random groups are never persisted

The approved first release ships balanced and explicit selection. It does not precompute random tasks, store deterministic generation schedules, or materialize unused pairs.

On fetch or assignment:

1. Revalidate project, user, eligibility, and later funding.
2. Prefer an existing task that still needs accepted answers and has not already been attempted by that worker.
3. Otherwise select eligible project items at fetch time using the configured balanced policy or consume the next explicit group.
4. Create a lightweight Task and its exact TaskInputs only for the group actually issued.
5. Create the leased Attempt and record actual presentation order.

Persisting issued TaskInputs is required evidence of what the worker saw. Individual answers reference stable TaskInput IDs, never ambiguous display labels such as “A.”

Selection replication and item coverage are separate axes:

- Per-question accepted-answer targets control how many valid answers an exact task needs.
- Coverage settings control how often underlying items appear across tasks.

Single-item work often makes those equivalent. Pairwise work may prefer diverse balanced exposures with one response per pair, or repeated exact pairs for agreement/adjudication. The design supports both.

Future king-of-the-hill and Elo-style selection fit the fetch-time boundary. They may use accepted responses and mutable rebuildable rating projections to choose the next matchup. The first release only establishes the selection-strategy interface; it does not implement those adaptive strategies.

### G. Task, attempt, presentation, and response lifecycle

```text
Task
├── TaskInputs
├── TaskQuestionProgress projections
└── Attempts
    ├── AttemptInputPresentations
    └── one Response
        └── QuestionResponses
```

Task lifecycle is `open → satisfied`, with `needs_attention` after repeated skips or failures and `cancelled` on deliberate project closure. It remains open while any required question lacks enough accepted answers.

Attempt lifecycle covers assigned or claimed, in progress, submitted, expired, released, and cancelled states. Claims use leases. Pairwise/input randomization is recorded per attempt so canonical input identity and actual display order are both auditable.

There are not separate draft and submission tables. One Response moves from mutable `draft` to immutable `submitted`. Every question write locks and revalidates the draft parent; submission locks the same parent, validates all outcomes, and freezes it atomically. Rework creates a new linked attempt/response rather than rewriting evidence.

### H. Questions can be explicitly skipped

Missing, answered, and intentionally skipped are distinct states. Every applicable question must have an explicit QuestionResponse outcome before submission:

```text
QuestionResponse
├── answered → typed value children
└── skipped  → reason, optional explanation, skipped_at
```

The organization-owned project determines whether skipping is allowed for each question and whether a reason is required. Skips are immutable after submission and remain queryable even if a later attempt answers the same task/question.

A skip does not satisfy the question's accepted-answer target. Repeated skips eventually move task/question progress to `needs_attention` rather than circulating forever. By default a worker is not served the same task twice, but an organization may deliberately reassign a follow-up, which creates a new attempt.

### I. Typed response values and initial advanced annotations

Initial scalar/choice families:

- text;
- integer;
- decimal;
- boolean;
- static single and multiple choice;
- task-input single and multiple choice; and
- ordered task-input ranking.

The first release also includes bounding boxes, polygon and raster-mask segmentation, and text spans. Audio/video time ranges are explicitly out of scope.

```text
QuestionResponse
├── scalar typed answer
├── StaticOptionAnswers
├── TaskInputAnswers
├── BoundingBoxes
├── PolygonRegions → ordered PolygonPoints
├── MaskRegions → immutable mask Asset
└── TextSpans
```

Spatial and span records reference the exact TaskInput and source dataset value they annotate. Bounding boxes and polygon points use normalized coordinates. Raster masks reference immutable assets and source dimensions. Text spans reference immutable text values and use one explicitly documented offset convention validated at submission.

Dataset value persistence and answer persistence remain separate because they have different ownership, lifecycle, provenance, and policies. They may share code-level value-family validation conventions.

### J. Review, progress, and raw results

Projects support automatic and manual review. Review decisions are append-only and target QuestionResponses, allowing partial acceptance/rejection within one submitted Response. A batch action may review a whole Response while persisting per-question decisions.

Accepted answers, pending answers, skips, rejections, and escalation state are maintained in rebuildable `TaskQuestionProgress` projections. Normalized attempts, responses, question outcomes, and reviews remain authoritative.

There is no canonical-resolution/final-answer layer in the first release. QuickTrain returns all accepted QuestionResponses. It does not automatically select one worker answer, synthesize consensus geometry, or create an adjudicated truth record. A future resolution feature can be additive.

Organizations access results through paginated GraphQL and asynchronous immutable exports. Default exports contain accepted answers and exact task/input provenance. Audit exports may include skips, pending/rejected outcomes, expired attempts, review history, and organization-visible compensation. Structured JSONL or manifests are valid export formats even though PostgreSQL persistence contains no JSONB content.

### K. Finance is a separate correctness boundary

Approved `QuickTrain.Finance` concepts:

- rate configuration;
- concrete WorkOffers shown/frozen at fetch;
- FundingReservations tied to attempts;
- LedgerAccounts, balanced LedgerTransactions and LedgerPostings;
- WorkSettlements;
- worker Earnings; and
- external Payouts.

Organization price and worker payout are separate amounts. Future rate models may pay per accepted response, per accepted question, via base plus components, quality bonuses, qualification bands, or zero-cost internal work. The exact commercial model and payment provider remain intentionally unresolved for the Finance change.

Fetching paid work must reserve the maximum organization charge atomically so QuickTrain does not offer work it cannot pay for. Skips, rejections, and partial answers remain neutral task facts; the pinned rate terms determine monetary treatment. A worker's offer is frozen at fetch and cannot change retroactively.

Money uses integer minor units and explicit currencies, never floats. Ledger transactions balance within one currency. Corrections use reversal postings. Worker earnings and external payouts are separate so payout failure never erases earned money. Provider deposits, transfers, fees, refunds, disputes, and webhooks reconcile to the internal ledger with idempotency keys.

### L. Reputation is deliberately simple and rebuildable

The first reputation change adds one global and zero-or-more organization-scoped WorkerReputation projections per user. Dimensions may include quality, reliability, agreement, experience, accepted/rejected counts, skips, and expirations.

There are no reputation-policy tables, policy versions, per-organization formulas, duplicated reputation-event table, or ReputationAdjustment resource. Calculation is hardcoded in application code. Authoritative evidence already exists in Attempts, QuestionResponses, skips, ReviewDecisions, and future consensus/adjudication records.

If the formula changes, a future batch recalculation job rebuilds every profile. Corrections happen in authoritative task/review evidence and flow into recalculation.

Skipping is tracked but is not automatically a negative signal because it may indicate a bad question or unsuitable source data. Organizations may configure straightforward project admission thresholds against global or organization-scoped reputation, but they do not customize the calculation. Reputation-based dynamic compensation is deferred; any eventual rate quote remains frozen at fetch.

### M. Authorization and GraphQL boundaries for later domains

Organization management actions require an active account, active membership, and explicit capabilities such as datasets/forms/projects management, task review, and finance management.

Workers cannot browse arbitrary datasets or unallocated tasks. `fetch_work` performs eligibility and funding checks and returns a leased attempt. Dataset values/assets become readable only through that attempt. Draft responses are writable only by the attempt owner. Submitted evidence is immutable. Reviewers cannot edit worker answers.

All application API behavior is GraphQL except `/healthz`. APIs expose deliberate lifecycle actions rather than generic mutation of immutable revisions, tasks, responses, reviews, reputation projections, or ledger postings.

### N. Concurrency, idempotency, jobs, and verification

Fetch/claim runs in one transaction, locks existing task progress or candidate coverage rows with `FOR UPDATE SKIP LOCKED`, selects or creates one actual task, creates the attempt and presentation, and later creates the offer/reservation. Direct assignment follows the same path.

Every question write and submit action locks the Response parent. Review/settlement locks the QuestionResponse, progress, reservation, and ledger rows required for a single atomic decision. Import revisions lock the stable DatasetItem. Related-data validation happens after locks, not as an unsafe read-modify-write precheck.

Task progress, item coverage, adaptive ratings, and reputation are rebuildable projections. Accepted task evidence and ledger postings are authoritative.

Synchronous paths include fetch, draft save, submit, review, and ledger settlement. Oban handles large imports, asset processing, exports, projection reconciliation, provider collection/payouts, and webhook follow-through through responsibility-specific workers.

Tests must cover lifecycle actions, policies, GraphQL integration, normalized type constraints, immutable revisions, form bindings, selection invariants, concurrent claims, save/submit races, skip/escalation, review, geometry/span bounds, ledger balance/idempotency, reputation projections, exports, and job idempotency. Selection tests assert invariants rather than brittle exact random sequences. Concurrency tests use independent database connections and deliberate barriers. Every implementation change finishes with OpenSpec validation and `mise run verify`.

### O. Explicit first-release exclusions recorded across the design

- External or externally hosted forms.
- JSONB-backed dataset content or answer payloads.
- Customer-specific database tables.
- Arbitrary nested dataset records in the first dataset change, despite the additive record envelope.
- Precomputed/random task materialization or unused stored pairings.
- King-of-the-hill and Elo selection implementations; only their extension boundary is established.
- Audio/video range annotations.
- Automatic consensus, canonical resolution, or final-answer synthesis.
- Per-organization reputation formulas, reputation policy/version/adjustment/event tables.
- A final commercial rate model or payment provider in the core Tasks change.
- Frontend implementation.
