## Purpose

Extend completed core task collection with verified image presentation and attributable spatial evidence after the detailed-media foundation is available.

## ADDED Requirements

### Requirement: Verified media facts remain tied to exact immutable sources
Image execution SHALL consume independently verified source facts identifying the exact immutable asset and content hash, positive pixel dimensions, supported format, and supported serving operation. Declared media types or client dimensions SHALL not satisfy verification. Mask compatibility SHALL additionally identify the exact immutable mask/source pair, their pixel dimensions, and the validated encoding. Detailed-media verification and serving SHALL be implemented separately; Tasks SHALL not parse bytes or invent dimensions. Fetch, image-access issuance, and submission SHALL recheck availability of the required capability and reject missing/mismatched facts without changing submitted evidence. Non-image collection SHALL not make these calls.

#### Scenario: An opaque ready asset is insufficient
- **WHEN** a source asset is byte-verified but lacks the required verified image facts
- **THEN** no image attempt is issued using that source

#### Scenario: Facts belong to a different revision's asset
- **WHEN** a worker or adapter supplies verified facts for an asset other than the exact bound source
- **THEN** the operation fails without substituting content or source dimensions

### Requirement: Image presentation uses attempt-owned access
An image work bundle SHALL require an active account/organization, current unblocked audience eligibility, exact attempt ownership, an unexpired live lease, and an active or paused project. External workers SHALL not require organization membership when their audience route qualifies. The bundle SHALL retain published PresentationElement/requirement/question identities, exact TaskInputs, and the persisted per-attempt display order. A `bound_value` element referencing an image requirement SHALL use that existing form contract; no new form presentation kind SHALL be required. Image-choice answers SHALL use existing task-input selection representations and count/slot validation, never display labels or a duplicate answer model.

#### Scenario: Two workers see different image order
- **WHEN** the same canonical inputs are shuffled differently for two attempts
- **THEN** each image presentation is attributable to its stored order while answers still reference canonical TaskInput IDs

### Requirement: Rendering authority does not broaden asset access
Worker image access SHALL be issued only for exact bound sources or the worker's authorized live mask attachment. Descriptors SHALL expire no later than the earlier of five minutes or the lease deadline and SHALL preserve encrypted transport, no-store/no-referrer, and approved destination restrictions. The separate media capability SHALL enforce its validated format, serving-origin, and response-header policy; this integration SHALL not infer inline safety from an opaque download or change ordinary download behavior. Revoked eligibility SHALL deny new access while previously issued descriptors retain only their bounded lifetime. Image access SHALL grant no unallocated asset, dataset, project, or response browsing.

#### Scenario: A worker requests an unrelated image
- **WHEN** an attempt owner supplies an asset that is absent from its authorized bound sources and mask attachments
- **THEN** no rendering descriptor or unrelated metadata is disclosed

### Requirement: Spatial evidence follows existing collection semantics
Spatial outcomes SHALL use the existing attempt/offered-question, draft revision, lease, immutable submission, skip, review, and escalation rules. A reviewer SHALL not edit geometry or substitute source media; a correction SHALL append a review decision, and rework SHALL create a linked new attempt. Source dimensions and media verification provenance used by submitted annotations SHALL be immutable and attributable to their exact input/assets. All source/label/region/point/mask collections SHALL have bounded typed Relay pagination with default 50/max 100.

#### Scenario: A geometry save races submission
- **WHEN** a spatial child replacement competes with submission of the same draft
- **THEN** either the complete edit is included in validation or it fails after submission freezes the parent and all descendants

### Requirement: Image results and exports preserve evidence without live rendering
Organization result readers SHALL require the existing active account/organization/membership checks, explicit project scope, and `tasks.results.read`. Accepted and audit results/exports SHALL include typed spatial coordinates, ordered polygon points, labels, exact source/value/asset identities, mask identity and verified dimensions, and the pinned review/presentation provenance. They SHALL use the core immutable export snapshot and SHALL NOT synthesize canonical geometry. Historical evidence inspection/export SHALL remain possible when live rendering is unavailable; new rendering access SHALL fail closed. Existing sealed non-image exports SHALL not be regenerated or modified. Image source and mask access through results SHALL require exact result authority, without bypass through generic asset capabilities.

#### Scenario: Media delivery goes offline after submission
- **WHEN** verified images can no longer be served but an authorized reviewer reads or exports prior submitted annotations
- **THEN** stored geometry and provenance remain readable/exportable while new rendering access fails explicitly

#### Scenario: An image result is corrected during export
- **WHEN** a review correction follows an already sealed export snapshot
- **THEN** that export retains its pinned spatial answer and decision evidence rather than following the latest verdict
