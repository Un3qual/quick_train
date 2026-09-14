## Context

**Implementation status: blocked.** Core collection must be implemented and archived, and the separate detailed-media/storage prerequisite still needs a concrete change name, durable spec paths, and a verified implementation. This document specifies the later integration; it does not make that integration ready to apply.

See `proposal.md` for the split and release order. `add-project-task-collection` now delivers complete core collection, including text spans and opaque downloads/exports, and rejects image-dependent contracts. This change owns the deferred image execution that previously prevented that core change from closing. Both core collection and the separate detailed-media foundation must be implemented before this follow-up is applied.

The existing form contract already contains image-intended requirements, `bound_value` presentation elements, image-choice renderers, and spatial definitions. Retain those IDs and representations. There is no separate image presentation-kind enum to add. The current detailed-media foundation is recorded but not yet a concrete implemented change; its required integration contract below is the entry gate for this follow-up, never for core collection.

## Goals / Non-Goals

**Goals:** Extend the completed Projects/Tasks model additively, preserve exact immutable source/answer provenance, and verify image execution against real verified-media and serving support.

**Non-Goals:** Reimplementing collection, introducing a second review/export pipeline, choosing formats/decoders/providers, or reserving schema/interfaces in core collection before this work starts. Text spans remain part of core collection.

## Decisions

### 1. A one-way dependency with an explicit entry gate

Implement and archive core collection first. The detailed-media change can proceed independently of core collection, but both must precede this integration. Before applying, confirm its durable spec and implementation provide:

- Immutable verified source facts bound to asset identity/hash, positive dimensions, and a supported image format.
- Verified mask/source compatibility bound to both immutable identities, matching pixel dimensions, and the chosen raster encoding.
- An approved image-serving operation with supported formats, enforced resource limits, isolated serving origin and response-header policy, encrypted direct endpoints, and bounded access lifetime.
- A compliant reachable storage adapter for the actual image/mask transfer paths. The separately selected adapter also owns live opaque-download/export transport verification; core already tests those byte/authorization contracts with its in-memory adapter.

Record the actual prerequisite change/spec paths in this design when they exist and rebase the proposed deltas on the archived core specs before implementation. If a prerequisite does not meet this contract, keep this follow-up blocked and update that separate change; do not weaken validation or reopen core completion. Decoders, supported formats, and provider configuration are decisions for that foundation, not unresolved choices in this integration.

Alternative: leave conditional spatial code and incomplete tests in core. Rejected because core would still depend on future work or carry unused resources. A follow-up keeps both completion criteria honest without losing scope.

### 2. Extend the existing supported-contract check

Replace core's unconditional rejection of image-dependent contracts with exact media validation during ProjectActivation under the existing Project lock. Validate all image-bound values across the frozen cohort and all published question/presentation references; reject the whole form on failure. No partial activation or silent removal of image questions. Unsupported unknown contracts still fail explicitly. Installing a provider alone does not change core behavior; installing this task integration is what adds the execution support.

Reserve `media_prerequisite_unavailable` for an absent or nonoperational capability, including unavailable compliant serving support. With that capability operational, an individual source that lacks verified facts or fails compatibility checks returns `invalid_project_configuration` with scoped source validation issues. Neither path activates a partial form; a source-content failure is not a missing deployment prerequisite.

Use the existing `Projects.ProjectActivation`, `Tasks.TaskSelection`, attempt eligibility, and work bundle. At fetch and image-access issuance, recheck the required facts/capability for exact allocated sources. Keep membership optional through the established external audience route; no new capability substitutes for attempt ownership. Return the existing PresentationElement/requirement/TaskInput identities and actual shuffled positions. Image choice stores the existing TaskInputAnswer selections, including single/multiple count bounds, rather than new image-answer tables.

Alternative: copy forms or materialize image-specific tasks. Rejected because frozen published definitions and actual TaskInputs already supply their identity and provenance.

### 3. Add only normalized spatial evidence

Generate BoundingBox, PolygonRegion/PolygonPoint, MaskRegion, and attempt/question mask-attachment resources inside `lib/quick_train/tasks/`. Keep TaskInput, exact source DatasetValue, and question label references within the same task/form-version boundaries using AshPostgres composite references and ordinary local checks. Use core Ash-generated UUID identities and returned parent IDs for all new rows; caller-supplied registration retry tokens are separate inputs. No JSONB geometry. The existing Response parent lock, expected revision, live-lease check, and submitted immutability govern every child create/update/delete and replacement.

Boxes use finite normalized decimals and strictly positive width/height. Polygons are simple nonzero-area rings with at least three distinct ordered points, implicit closure, no crossings/repeated closing point, and coordinates in `[0,1]`. Multiple regions are supported; a region does not encode holes or a multipolygon. Preserve published annotation constraints without adding region/point limits or a combined annotation budget. Use the core Project/Task/Attempt/Response lock order and post-lock checks for every spatial draft mutation. Zero regions is a valid answer only where minimum zero allows it.

MaskRegion pins a ready immutable mask Asset, exact source Asset/value, verified positive source dimensions, and immutable verification provenance. The media foundation verifies decoding/encoding and pixel compatibility; Tasks only consumes the result. Never accept client-declared dimensions as verified facts. Recheck media availability at submission but do not require it to read stored historical geometry.

### 4. Scoped upload and serving authority

Add deliberate Tasks mask registration/finalization/attachment actions tied to an offered raster question and a live eligible owned attempt. Assign the project's organization and retain existing enforced byte caps, hash/size verification, immutable sealing, and canonical deduplication. Store attempt/question ownership and result-access scope from registration onward, including pending assets, and preserve those links when finalization selects a canonical asset. These links grant no attachment, download, or rendering authority while pending; they authorize only scoped upload/finalization work. Worker attachment and content access require successful finalization of that registration's verified upload plus the existing lease, authorization, and applicable media checks. A same-organization UUID or known hash alone never authorizes another worker's mask.

Require a caller-supplied UUID request key unique per attempt/question, bound to immutable hash/size/media arguments. Use native UUID storage and the core Project/Task/Attempt/Response lock order with post-lock owner/eligibility/lease/state checks. Existing keys return their recorded registration state; changed arguments conflict. For absent keys, validate only the supplied facts under existing upload rules and create a pending Asset directly without the general registration canonical lookup/reuse shortcut. Admission and returned metadata must not vary with canonical existence or facts. Use the core Ash UUID generation path for registration and Asset IDs, then atomically persist the new registration/key and pending Asset/staging identity, then perform storage I/O outside the transaction. Every new key verifies its own upload, even when canonical content exists. Successful finalization establishes attachment authority for the offered attempt/question and resolves canonical content through the existing deduplication rules. Later retries retain that canonical resolution. Pending retries resume interrupted storage work using the same Asset and destination while staging access remains valid; they never rerun general registration or extend expiry. Resolve canonical matches/conflicts through that pending Asset's existing finalizer only after its own pinned bytes pass hash/size verification, whether canonical content predates admission or appears concurrently. Missing/mismatched staging returns its existing upload failure without canonical disclosure. This removes the pre-admission lookup that would otherwise expose an organization's content to an attempt-only worker; it adds no new state or verification mechanism. Terminal failed/expired retries return the recorded outcome without upload access or revival; replacement uses a fresh UUID and current authorization. Retain the existing per-file Assets/provider behavior, without task-level registration quotas, aggregate-byte allowances, refund accounting, or usage counters.

Derive registration outcomes from the existing Assets lifecycle: committed `content_mismatch` or `asset_identity_conflict` means failed, failed `staging_expired` means expired, and ready or `duplicate_content` resolves canonical ready content. Keep the existing asset lock, finalizer-claim, and expiry checks. Invalid access descriptors return no access or credentials and retain the already-committed registration/Asset; the ordinary Assets no-row failure applies to its separate validate-before-persist registration path. Transport errors, storage timeouts, missing staging, and interrupted requests likewise leave the registration pending unless a terminal Assets outcome has committed; a lost success response resolves the committed canonical result. This requires no separate failure classifier or registration lifecycle. Finalizing a replacement upload does not change the answer or supersede other finalized registrations. The existing whole-question save with `expected_revision` selects the current MaskRegion children atomically, supporting multiple masks within published constraints. Submission and answer rendering use those children; registration history alone does not make a mask part of the answer. Retain old registration provenance without adding active/historical flags or deleting canonical content.

Extend core's protected export-asset rules to mask assets/results. An independently authorized source or independently verified upload of identical bytes can grant access to bytes, without revealing result associations. Generic `assets.read`/`assets.manage`, registration, or canonical-reuse paths must not bypass task-result authority. Workers receive only lease-bounded authorized source/mask access; organization result readers use the existing results capability. Ordinary opaque downloads retain attachment/octet-stream/nosniff. Image rendering uses only the foundation's separately approved serving policy.

### 5. Reuse review, evidence snapshots, and exports

Review remains append-only per QuestionResponse with the existing self-review denial, expected predecessor, and idempotency. Follow-up attempts carry new geometry without mutating old answers. Extend typed result relationships and JSONL serialization to spatial children and verified source/mask provenance. Add `bounding_box`, `polygon_region`, `polygon_point`, and `mask_region` to the core evidence kinds in the new format version, with the same per-kind ID-range selection, streamed output, and exact record accounting, without an export-volume ceiling. The core export snapshot pins the submitted outcomes and review decisions; their immutable children can be streamed without a new snapshot subsystem. Keep all new child collections keyset-paginated. Within each polygon, typed point connections order and cursor by authored position then immutable point ID, preserving ring order across pages. JSONL retains its global kind/ID order and carries authored point position explicitly.

Image result context uses the core result-scoped definition/bound-value projections: label text and source content remain interpretable without separate Forms/Datasets grants, and exact source-asset access uses result authority. Never serialize mutable live media availability or newly issued rendering URLs into historical evidence. Source facts/IDs and submitted geometry remain readable when serving is offline. Original non-image export bytes remain sealed and unchanged; new image exports use an explicit format-version increment with golden evidence fixtures covering both supported versions.

### 6. Verification and code layout

Start with installed Ash generators and generate/review additive migrations and snapshots. Extend the existing Projects/Tasks workflows, GraphQL schema, and focused tests; do not add a new domain. Add `test/quick_train/task_media_test.exs` and image cases to existing allocation/response/result/GraphQL suites. Test actual source/mask compatibility, image choice, invalid geometry, input/label substitution, revoked ownership, save/submit races, and byte-publication retries. Real media/provider integration is required here; fake success facts alone cannot complete this change. Keep separate offline tests proving the original non-image flows remain usable.

## Risks / Trade-offs

- **Prerequisite details can evolve before implementation** -> Check the explicit contract against the implemented foundation, record its spec paths, and rebase the dependent deltas before applying.
- **Untrusted media or expired access** -> Use only verified immutable facts and approved serving support, cap descriptors by lease/five minutes, and reject missing capability without inventing fallback rendering.
- **More response child types** -> Keep the existing Response transaction boundary and scope constraints; add meaningful geometry/concurrency tests rather than a second lifecycle.
- **Image serving may be unavailable later** -> Retain immutable stored evidence independently, fail new media access explicitly, and keep non-image operations independent.

## Migration Plan

1. Verify/archive core collection and verify the implemented detailed-media/real-storage prerequisites; update dependency links and resolve any drift in these deltas.
2. Generate additive spatial/attachment migrations and snapshots, preserving all published definitions, existing projects, attempts, responses, review decisions, and export bytes.
3. Extend supported activation and typed API operations only with the verified integration deployed. Previously rejected draft image projects can then be explicitly activated; existing frozen projects do not gain or change inputs/questions.
4. Verify up/down/reapply in a disposable database and both media-enabled and media-unavailable paths. For production rollback, stop new image allocation and preserve existing evidence; do not drop spatial tables holding real answers.
5. Run `mise run openspec.validate` and `mise run verify`; archive this follow-up only after its real media integration checks and all tasks pass. This status has no effect on completion of the earlier core change.
