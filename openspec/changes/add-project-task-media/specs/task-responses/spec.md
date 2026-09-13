## ADDED Requirements

### Requirement: Spatial annotation provenance is exact
Each spatial region SHALL identify the exact TaskInput, its bound source DatasetValue, and a label from the question's published label set. The source SHALL match the question's required image source and exact allocated immutable revision. Region counts SHALL satisfy the published question bounds; zero regions SHALL be an answered outcome only when its minimum is zero. Foreign labels, wrong source values, and unallocated inputs SHALL fail. Every spatial write SHALL use the core Project/Task/Attempt/Response lock order, post-lock owner/eligibility/lease/state checks, draft revision check, and immutable submission boundary. No spatial payload SHALL be persisted as JSONB.

#### Scenario: An annotation targets an unbound field
- **WHEN** a worker supplies a valid value from the allocated revision that is not the question's bound source
- **THEN** the write fails without attaching the region to that value

### Requirement: Bounding boxes and polygons use normalized valid geometry
Bounding boxes SHALL use finite normalized coordinates with `0 <= x_min < x_max <= 1` and `0 <= y_min < y_max <= 1`. Polygon regions SHALL contain at least three distinct ordered points within `[0,1]`, have nonzero area, and form a simple non-self-intersecting ring with implicit closure. Repeated closing points, holes within one region, and non-finite coordinates SHALL be rejected. Multiple independent regions SHALL be permitted within the published question constraints. Image execution SHALL require the separately implemented verified-media and serving prerequisites; opaque readiness alone SHALL not validate image sources.

#### Scenario: Invalid geometry is submitted
- **WHEN** a box has negative width or a polygon crosses itself or contains an out-of-range coordinate
- **THEN** submission fails without persisting an immutable invalid annotation

#### Scenario: Media capability is unavailable
- **WHEN** an image attempt cannot resolve the required verified source facts or supported image-serving capability
- **THEN** fetch/submission fails closed rather than trusting client image metadata

### Requirement: Raster masks reference compatible immutable assets
A raster mask SHALL reference a ready immutable mask asset and exact source asset/value with verified positive source dimensions. A separately implemented media capability SHALL verify compatible encoding and source/mask pixel dimensions and bind that result to both immutable asset identities; client dimensions and declared media types SHALL not satisfy it. Mask registration/finalization SHALL require a live eligible owning attempt and an offered raster-mask question, use the project's organization and existing upload-cap/hash/sealing rules, and create an explicit attempt/question attachment authority. Canonical deduplication SHALL preserve that authority without granting general asset reuse/browsing rights. Finalization SHALL authorize attachment without modifying the draft. Only the core whole-question save with `expected_revision` SHALL select or replace the current MaskRegion children; submission and answer rendering SHALL use those children, never infer an answer from the latest registration. Removing a mask from the draft SHALL not delete its registration history or mutate canonical bytes. Multiple masks SHALL remain valid where the published question permits them. Tasks SHALL not decode files or select a provider in this change.

#### Scenario: The source and mask have different dimensions
- **WHEN** the media capability reports incompatible dimensions for the exact source and mask
- **THEN** submission rejects the mask

#### Scenario: A worker borrows another attempt's asset
- **WHEN** a worker references a ready mask without authorized attachment provenance for the offered question
- **THEN** the answer fails even if the asset belongs to the same organization

#### Scenario: A worker replaces a draft mask
- **WHEN** an authorized worker uploads new mask content to replace a draft attachment
- **THEN** registration uses a new request key and verifies the replacement upload without changing the draft; a subsequent whole-question save with the current `expected_revision` atomically replaces the selected MaskRegion children while preserving registration history

### Requirement: Spatial response inspection is typed and paginated
Spatial answers SHALL follow published annotation constraints and the existing request handling, with no additional region/point ceiling or combined annotation budget. All coordinates and typed children SHALL be validated before immutable submission. Spatial child reads SHALL follow the existing stable Relay keyset pagination conventions. Within each polygon, point connections SHALL sort by authored position then immutable point ID and use that same composite key in cursors to preserve ring order across pages.

#### Scenario: A polygon spans multiple result pages
- **WHEN** a submitted polygon has more points than fit on one result page
- **THEN** all original points are reachable exactly once in authored ring order using position/ID cursors, even when UUID order differs from point order
