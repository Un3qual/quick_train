## MODIFIED Requirements

### Requirement: Attempt-owned published-contract inspection
The system SHALL allow an eligible owner of an unexpired live task attempt in an active or paused project to inspect the exact published form contract pinned by that attempt through its work bundle without `forms.read` or organization membership. Every access SHALL check active account/organization, current worker audience route, absence of a block, and exact attempt ownership. The returned contract SHALL include every question in the pinned published form and preserve published definition identities, typed constraints, options, labels, and authored presentation order. It SHALL grant no general form listing, draft access, other-version traversal, reverse organization relationships, or authoring action. It SHALL use bounded Relay connections with default 50/max 100 and SHALL cease on expiry, release, cancellation, submission, or lost eligibility. Publication semantics and the opaque-file boundary SHALL remain unchanged.

#### Scenario: An external worker reads their allocated contract
- **WHEN** an eligible non-member opens their current attempt work bundle
- **THEN** it includes that attempt's pinned published contract while general form APIs still deny access

#### Scenario: A worker changes the version identifier
- **WHEN** the same worker asks for an unallocated draft or different published version
- **THEN** the request fails without exposing its definitions

### Requirement: Result-scoped published-definition inspection
An active member authorized for `tasks.results.read` in an active organization and explicit project scope SHALL be able to inspect the immutable published presentation and question/option/label definitions referenced by that project's eligible result evidence through Tasks without `forms.read`. Reads and exports SHALL preserve original definition identities and human-readable content, question renderer/input references, and complete typed constraint records and fields, including explicit absent-record/null-bound distinctions and published default semantics. They SHALL include the complete pinned PresentationElement sequence with each element's kind, position, text, and question/requirement references. Question/option/label definitions referenced by those placements SHALL be available as context. Every attempt SHALL cover all questions in its pinned published form; inspection SHALL derive that question set from the form without a separate attempt-specific offered-question record. They SHALL expose only this referenced contract through bounded typed result relationships, not general form listing, drafts, unrelated questions/versions, or reverse organization traversal. Existing general form authorization SHALL remain unchanged.

#### Scenario: A result reader resolves an option label
- **WHEN** an authorized result-only reader follows a static-option answer to its pinned option
- **THEN** Tasks returns the original option key/label and question context, including its renderer and complete typed constraints, while arbitrary form-definition access remains denied

#### Scenario: A result reader inspects a pinned presentation
- **WHEN** a result-only reader follows an included attempt to its presentation
- **THEN** Tasks returns its original published element sequence and referenced contract with bounded pagination, while other versions and unreferenced definitions remain denied
