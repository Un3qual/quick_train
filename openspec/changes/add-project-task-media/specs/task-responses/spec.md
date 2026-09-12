## MODIFIED Requirements

### Requirement: Response writes are bounded and explicitly exposed
GraphQL SHALL expose deliberate typed save/submit operations and bounded typed outcome inspection; generic submitted-outcome/child update and delete mutations SHALL not exist. Apply at most 200 offered questions, 64 KiB text per answer, 1 KiB reason, 16 KiB explanation, and 1,000 spans per question, alongside published form bounds and the existing HTTP body limit. The per-response annotation ceiling SHALL be 10,000 combined child rows, counting each TextSpan, BoundingBox, PolygonRegion, PolygonPoint, and MaskRegion once; this replaces the core text-only total rather than granting a separate budget to each family. Whole-question replacement SHALL check the resulting response total under its existing lock. Impossible published minimums SHALL reject project activation; tighter execution ceilings SHALL be disclosed. Oversized operations SHALL fail atomically and all collections SHALL use Relay keyset pagination, default 50/max 100.

#### Scenario: A span answer exceeds its execution limit
- **WHEN** a draft write supplies 1,001 text spans
- **THEN** the whole question write fails without replacing the previous draft answer

#### Scenario: Text and spatial annotations share one budget
- **WHEN** a response contains 9,000 text spans across questions and a draft replacement would leave another 1,001 spatial child rows
- **THEN** the write fails atomically even if every per-question and per-polygon bound is met; polygon regions and their points both count toward the combined total

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
Spatial writes SHALL accept at most 1,000 regions per question and 1,000 points per polygon within the combined per-response annotation budget defined by `Response writes are bounded and explicitly exposed`, subject to tighter published bounds and the existing request-body limit. All coordinates, counts, and typed children SHALL be validated before immutable submission. Published minimums that exceed these execution limits SHALL reject activation. Spatial child reads SHALL use stable Relay keyset pagination with default 50/max 100.

#### Scenario: A polygon exceeds its execution limit
- **WHEN** a draft write supplies 1,001 points
- **THEN** the complete question write fails without replacing the previous draft outcome
