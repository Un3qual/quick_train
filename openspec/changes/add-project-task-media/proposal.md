## Why

Image tasks need verified source facts and compliant media delivery, while ordinary task collection can ship without them. This change preserves the image-dependent portion split from `add-project-task-collection` and implements it after both core collection and the separately scoped detailed-media foundation are available.

## What Changes

- Extend project activation to accept image input requirements, image presentation elements, image-choice renderers, and spatial questions only when the exact source assets have verified media facts and supported delivery.
- Add attempt-scoped verified image presentation and keep canonical TaskInput identity separate from display order. Image choice continues using existing typed task-input selections.
- Add normalized bounding-box, polygon-region, and raster-mask responses with exact TaskInput/source-value/label provenance; retain the core draft, lease, submission, review, and export boundaries.
- Add scoped worker mask registration/finalization and attachment, verified source/mask compatibility, and result-authorized image/mask access.
- Verify integration against the real detailed-media capability and compliant reachable storage, including immutable image evidence in results and exports.

Explicit non-goals:

- Reopening or blocking completion of `add-project-task-collection`; text spans and scalar/non-image choice/ranking collection stay in that earlier change.
- Choosing or implementing image decoders, supported file formats, sanitizers, serving origins/headers, or storage providers. The separate detailed-media/storage change owns those decisions and their implementation.
- A new task/response/review state machine, a media plugin framework, frontend work, audio/video ranges, consensus, Finance, or Reputation.

## Capabilities

### New Capabilities

- `task-media`: verified attempt-scoped image presentation and preserved image evidence in collection results and exports.

### Modified Capabilities

- `projects`: extend the core supported-contract requirement to image execution with verified prerequisites.
- `task-responses`: add exact spatial annotation provenance, bounding boxes, polygons, and masks under existing atomic response semantics.
- `assets`: add attempt-scoped mask registration and protected mask-result access while preserving core source/download/export authority.

## Impact

- Apply and archive `add-project-task-collection` first so its `projects` and `task-responses` specifications exist in the main spec tree. This follow-up's deltas are based on that proposed baseline; rebase them against the then-current main specs before implementation.
- Also require the detailed-media/storage work recorded in [the future architecture](../record-future-product-architecture/design.md#deferred-file-interpretation-and-http-storage-integration). It must provide immutable source/hash/dimension facts, source/mask validation, approved rendering access, and real transfer endpoints. Its eventual change name is not assigned here; its acceptance contract is explicit in this design.
- Adds Ash resources and additive migrations inside the existing Tasks domain, extends Projects/Tasks GraphQL actions and Assets authorization, and preserves all existing projects, attempts, and submitted/exported evidence.
- This change is intentionally blocked on those prerequisites. The dependency runs toward this follow-up only; core collection can be completed and archived first.
