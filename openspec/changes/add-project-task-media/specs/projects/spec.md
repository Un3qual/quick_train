## MODIFIED Requirements

### Requirement: Activation accepts only implemented task contracts
Activation SHALL continue supporting scalar answers, static/task-input choices, rankings, text spans, and asset requirements intended for opaque download. With task-media execution implemented, it SHALL additionally support `image` input requirements, bound-value presentation referencing those requirements, `image_choice` renderers, and bounding-box, polygon-region, and raster-mask questions. Image-dependent contracts SHALL require the separate media capability to supply immutable verified source/hash/dimension facts and compliant image-serving support for every applicable enrolled source. Missing capability SHALL return `media_prerequisite_unavailable`; incompatible or unverified source content SHALL fail activation with scoped validation issues. Other unimplemented contracts SHALL return `unsupported_task_contract`. Activation SHALL validate the whole pinned form and cohort atomically and SHALL not omit unsupported elements/questions or substitute a different form version. A provider alone SHALL not enable these contracts without task-media integration. Existing published definitions and active non-image projects SHALL remain unchanged; the core collection change SHALL remain independently complete.

#### Scenario: Image execution requires both integration and verified media
- **WHEN** an authorized manager activates an image project with task-media installed and all required source facts and serving support available
- **THEN** it activates under the same frozen cohort/form/policy contract as other projects

#### Scenario: A mixed form is validated as a whole
- **WHEN** a form combines supported text questions with image requirements whose source content cannot be verified
- **THEN** activation fails atomically rather than issuing a partial contract

#### Scenario: Text collection works with no media support
- **WHEN** a valid scalar, non-image choice/ranking, or text-span project is activated without the detailed-media component
- **THEN** it proceeds through collection without a media lookup

#### Scenario: Media support is missing
- **WHEN** task-media integration is installed but the configured media capability cannot provide the required verified source facts or serving support
- **THEN** activation returns `media_prerequisite_unavailable` and leaves the project draft
