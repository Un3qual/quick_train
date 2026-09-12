## ADDED Requirements

### Requirement: Spatial annotation provenance is exact
Each spatial region SHALL identify the exact TaskInput, its bound source DatasetValue, and a label from the question's published label set. The source SHALL match the question's required image source and exact allocated immutable revision. Region counts SHALL satisfy the published question bounds; zero regions SHALL be an answered outcome only when its minimum is zero. Foreign labels, wrong source values, and unallocated inputs SHALL fail. Every spatial write SHALL use the existing Response lock, current owner/eligibility/lease checks, draft revision check, and immutable submission boundary. No spatial payload SHALL be persisted as JSONB.

#### Scenario: An annotation targets an unbound field
- **WHEN** a worker supplies a valid value from the allocated revision that is not the question's bound source
- **THEN** the write fails without attaching the region to that value

### Requirement: Bounding boxes and polygons use normalized valid geometry
Bounding boxes SHALL use finite normalized coordinates with `0 <= x_min < x_max <= 1` and `0 <= y_min < y_max <= 1`. Polygon regions SHALL contain at least three distinct ordered points within `[0,1]`, have nonzero area, and form a simple non-self-intersecting ring with implicit closure. Repeated closing points, holes within one region, and non-finite coordinates SHALL be rejected. Multiple independent regions SHALL be permitted within count limits. Image execution SHALL require the separately implemented verified-media and serving prerequisites; opaque readiness alone SHALL not validate image sources.

#### Scenario: Invalid geometry is submitted
- **WHEN** a box has negative width or a polygon crosses itself or contains an out-of-range coordinate
- **THEN** submission fails without persisting an immutable invalid annotation

#### Scenario: Media capability is unavailable
- **WHEN** an image attempt cannot resolve the required verified source facts or supported image-serving capability
- **THEN** fetch/submission fails closed rather than trusting client image metadata

### Requirement: Raster masks reference compatible immutable assets
A raster mask SHALL reference a ready immutable mask asset and exact source asset/value with verified positive source dimensions. A separately implemented media capability SHALL verify compatible encoding and source/mask pixel dimensions and bind that result to both immutable asset identities; client dimensions and declared media types SHALL not satisfy it. Mask registration/finalization SHALL require a live eligible owning attempt and an offered raster-mask question, use the project's organization and existing upload-cap/hash/sealing rules, and create an explicit attempt/question attachment authority. Canonical deduplication SHALL preserve that authority without granting general asset reuse/browsing rights. Tasks SHALL not decode files or select a provider in this change.

#### Scenario: The source and mask have different dimensions
- **WHEN** the media capability reports incompatible dimensions for the exact source and mask
- **THEN** submission rejects the mask

#### Scenario: A worker borrows another attempt's asset
- **WHEN** a worker references a ready mask without authorized attachment provenance for the offered question
- **THEN** the answer fails even if the asset belongs to the same organization

### Requirement: Spatial responses have bounded execution limits
Spatial writes SHALL accept at most 1,000 regions per question, 1,000 points per polygon, and 10,000 total annotation child rows per response including text spans, subject to tighter published bounds and the existing request-body limit. All coordinates, counts, and typed children SHALL be validated before immutable submission. Published minimums that exceed these execution limits SHALL reject activation. Spatial child reads SHALL use stable Relay keyset pagination with default 50/max 100.

#### Scenario: A polygon exceeds its execution limit
- **WHEN** a draft write supplies 1,001 points
- **THEN** the complete question write fails without replacing the previous draft outcome
