## Purpose

Let organizations author and publish reusable, immutable task contracts containing typed input requirements, ordered presentation elements, and question definitions independently of dataset content and task responses.

## ADDED Requirements

### Requirement: Organization-scoped form access
The system SHALL require an active authenticated account, active owning organization, active membership in that organization, and `forms.read` for form inspection or `forms.manage` for authoring and publication. Each caller-initiated operation SHALL resolve its target within an explicit organization scope. The same checks SHALL apply to nested definitions and relationships. An identifier, a published state, or a capability in another organization SHALL NOT grant access. Organization membership SHALL remain optional for accounts generally, but a non-member SHALL have no form access in this release. Management capability SHALL authorize the result of a successful mutation without implicitly granting general read access.

#### Scenario: Authorized author creates a form
- **WHEN** an active member with `forms.manage` creates a form in their active organization
- **THEN** the system creates that organization's form and returns the mutation result

#### Scenario: Reader cannot publish
- **WHEN** an actor with `forms.read` and without `forms.manage` attempts to publish a version
- **THEN** the operation is denied without changing it

#### Scenario: Access fails closed across all read paths
- **WHEN** an unauthenticated actor, inactive account, inactive organization, inactive member, non-member, or actor without the required capability requests a form or nested definition
- **THEN** the system denies access without exposing the definition or its existence through a different error for a foreign identifier

#### Scenario: Foreign child is supplied to an authorized mutation
- **WHEN** an authorized author supplies an option, question, requirement, or version belonging to another organization
- **THEN** the mutation fails without exposing or modifying that foreign record

### Requirement: Stable forms and independently editable numbered versions
The system SHALL give each form a stable identity and organization-unique nonempty key, and each version a unique positive increasing number within its form. Each version SHALL own its title, description, input definitions, presentation, questions, options, and labels. New versions SHALL start as drafts; multiple drafts SHALL be allowed. Creating an empty draft or copying a published version of the same form SHALL allocate a new number. Both operations SHALL share one per-form serialization boundary held from before reading the next number until commit or rollback. A competing allocation SHALL wait for that outcome and then read the committed state, so committed version numbers increase strictly in commit order. A copy SHALL preserve authored values, keys, and ordering while allocating new identities for every owned record and remapping every internal reference. Draft sources, foreign forms, and foreign organizations SHALL be rejected as copy sources. Copying SHALL be atomic. This release SHALL expose no version or form deletion operation; numbers assigned to committed versions SHALL never be recycled. A rolled-back creation or copy SHALL consume no version number and SHALL expose no destination version; a later successful transaction can use that uncommitted candidate number. Organization ownership, parent identities, version numbers, and authored keys SHALL be immutable after creation; authors can replace an unreferenced draft definition by removing it and creating another.

#### Scenario: Concurrent draft creation
- **WHEN** two authors create drafts of the same form concurrently
- **THEN** both successful drafts have distinct increasing version numbers

#### Scenario: Allocation rollback precedes a competing creation
- **WHEN** one create or copy transaction has candidate version 2 and another creation starts before it rolls back
- **THEN** the competing creation waits, then can commit version 2; it cannot commit version 3 while the first candidate remains unresolved

#### Scenario: Author copies a published contract
- **WHEN** an author creates a draft from a published version of the same form
- **THEN** the complete copied contract uses new record identities, its references point only to copied definitions, and edits leave the source version unchanged

#### Scenario: Copy fails midway
- **WHEN** any definition cannot be copied successfully
- **THEN** no partial destination version is persisted and no version number is consumed

### Requirement: Typed reusable input requirements
The system SHALL let a draft define input slots with version-unique nonempty keys, positive minimum item counts, and finite maximum item counts no smaller than their minimums. Each slot SHALL own field requirements with slot-unique keys, a value family (`text`, `integer`, `decimal`, `boolean`, `utc_datetime`, or `asset`), single-value cardinality, and explicit requiredness. Definitions SHALL NOT contain concrete dataset, field, item, revision, or asset bindings. Repeated slot items SHALL be distinct from repeated values inside a dataset field; repeated or nested field requirements SHALL be rejected in this release. The `utc_datetime` family SHALL describe UTC date-time values using the same family identifier as datasets, without an alias or conversion. Non-asset requirements SHALL have no intended-use value; creation or update with a non-null intended use on a non-asset family SHALL be rejected, including a family change that retains an asset-only value. An asset requirement SHALL declare intended use as `download` or `image`; `image` SHALL describe a future consumer requirement and SHALL NOT certify any actual file or permit inline delivery.

#### Scenario: Pairwise input is reusable
- **WHEN** an author defines `candidate` with minimum and maximum item count two and a required `body` text field
- **THEN** the version describes two input items using the same text requirement without copying questions or requiring a dataset identifier

#### Scenario: Unsupported cardinality is rejected
- **WHEN** an author supplies a nonpositive slot minimum, a maximum below its minimum, or a repeated or nested field requirement
- **THEN** the write fails without persisting the invalid definition

#### Scenario: Asset intent cannot accompany a scalar field
- **WHEN** an author supplies image or download intent for a text or other non-asset requirement, or changes an asset requirement to a non-asset family while retaining that intent
- **THEN** the write fails without persisting contradictory type metadata

#### Scenario: Input contract is independent of data access
- **WHEN** an authorized form reader inspects a field requirement
- **THEN** the result contains its type and intended use without dataset content or storage access

### Requirement: One normalized presentation sequence
The system SHALL define one ordered sequence per version containing typed instructions, headings, section markers, bound-value placements, and question placements. Each element SHALL own its kind-specific text or reference directly under one stable element identity. Positions SHALL be unique nonnegative integers within the sequence, with gaps permitted. Instructions, headings, section markers, prompts, and labels SHALL contain plain text rather than executable HTML, scripts, or embedded external-form references. Instruction and heading text SHALL contain at least one non-whitespace character, enforced on creation and update. Section-marker text can be empty because the marker also serves as a structural boundary for an unnamed section. A section marker SHALL introduce a section for following elements until the next marker, without nested containers. Bound-value placements SHALL reference an input field requirement from the same version and describe presentation for all items in its slot in eventual task presentation order. Question placements SHALL reference a question from the same version. Each published question SHALL appear exactly once. Reordering SHALL atomically accept a complete permutation of the current element IDs and reject duplicates, omissions, or foreign IDs. A successful reorder SHALL canonicalize positions to consecutive integers starting at zero in the supplied ID order, including for previously sparse sequences; it SHALL preserve record identities.

#### Scenario: Ordered pairwise presentation
- **WHEN** an author places instructions, a candidate body requirement, and a choice question in order
- **THEN** inspection returns that exact sequence with typed references independent of future dataset items

#### Scenario: Blank content-only presentation text is rejected
- **WHEN** an author creates or updates an instruction or heading with empty or whitespace-only text
- **THEN** the write fails without persisting an empty content element

#### Scenario: Reordering is atomic
- **WHEN** an author swaps two elements using a complete valid permutation
- **THEN** readers see the committed old or new order, never duplicate positions or a partially applied order, and the new positions are consecutive integers starting at zero even if the old sequence had gaps

#### Scenario: Invalid reference or referenced deletion
- **WHEN** an author references a question from another version or removes a definition still referenced by a placement or question
- **THEN** the write fails and existing references remain intact

### Requirement: Typed question families and renderer compatibility
The system SHALL store questions with version-unique nonblank keys containing at least one non-whitespace character, nonblank plain-text prompts containing at least one non-whitespace character, an answer family, a compatible renderer, and typed family-specific constraints. Blank prompts SHALL be rejected on question creation and update. It SHALL support the following combinations and reject other combinations:

| Answer family | Compatible renderers |
| --- | --- |
| text | text_input, text_area |
| integer | integer_input, stars, likert |
| decimal | decimal_input |
| boolean | checkbox, toggle |
| static_single_choice | radio, dropdown |
| static_multiple_choice | checkbox_group |
| task_input_single_choice | radio, dropdown, pairwise, image_choice |
| task_input_multiple_choice | checkbox_group, image_choice |
| task_input_ranking | ranking |
| bounding_boxes | bounding_boxes |
| polygon_regions | polygon_regions |
| raster_masks | raster_masks |
| text_spans | text_spans |

Text constraints SHALL support optional nonnegative minimum and maximum Unicode code-point lengths. Integer and decimal constraints SHALL support optional inclusive minimum and maximum values, preserving decimal precision. Integer questions and their supplied bounds SHALL use the signed 32-bit range −2,147,483,648 through 2,147,483,647 supported by GraphQL Int; for `integer_input`, an omitted bound SHALL mean the corresponding endpoint of that range. Paired bounds SHALL satisfy minimum no greater than maximum. Stars and Likert SHALL require both bounds to be explicitly supplied before publication, with no implicit endpoints, and SHALL permit at most 200 discrete values (`maximum - minimum + 1 <= 200`). Supplied oversized ranges SHALL be rejected on creation or update; incomplete drafts can omit bounds but SHALL fail publication until both are supplied. Boolean questions SHALL have no unrelated scalar or selection constraints. Selection and annotation constraints SHALL use explicit count bounds as specified below. Unknown families, renderer values, and configuration fields SHALL be rejected. Changing family or renderer SHALL reject incompatible existing children or constraints rather than silently dropping them. No generic JSON configuration or answer payload SHALL substitute for the typed contract. Per-question answer targets, worker skipping, and review policy SHALL be left to Projects and Tasks.

#### Scenario: Blank question prompt is rejected
- **WHEN** an author creates or updates a question with an empty or whitespace-only prompt
- **THEN** the write fails without persisting a question lacking question text

#### Scenario: Renderer changes without changing value family
- **WHEN** an author changes a compatible integer question from integer input to stars with explicit integer bounds 1–5
- **THEN** its answer family remains integer and its renderer and typed constraints reflect the new contract

#### Scenario: Discrete integer renderers remain bounded
- **WHEN** an author publishes a stars or Likert question with either bound omitted, or writes explicit bounds containing more than 200 integer values
- **THEN** the operation fails; explicit ordered bounds containing at most 200 values satisfy the range-size check

#### Scenario: Incompatible configuration is rejected
- **WHEN** an author selects a text renderer for an integer question, supplies reversed or out-of-range integer bounds, or attaches choice constraints to a boolean question
- **THEN** the write fails without partially changing the question

### Requirement: Static choices and dynamic input choices remain distinct
Static-choice questions SHALL own ordered options with question-unique nonblank keys containing at least one non-whitespace character and nonblank plain-text labels containing at least one non-whitespace character. Blank option labels SHALL be rejected on creation and update. Input-choice and ranking questions SHALL reference one input slot in the same version directly from the question and SHALL NOT own static options. Drafts MAY omit the input-slot reference until publication. A source-requirement reference SHALL require an input-slot reference; clearing both SHALL remove the input source without replacing question identity. Single-choice questions SHALL require exactly one selection; multiple-choice questions SHALL define a positive minimum and finite maximum selection count with minimum no greater than maximum; ranking SHALL order every input item of its referenced slot without ties or omissions. Publication SHALL require at least two options for static choice and at least two guaranteed input items for input choice or ranking. For static multiple choice, the maximum SHALL be no greater than the option count. For input multiple choice, the maximum SHALL be no greater than the slot minimum, so the constraint is feasible for every allowed slot size. Pairwise SHALL require a slot fixed at exactly two items. Image choice SHALL additionally reference a required, single asset field requirement with intended use `image` from its referenced slot. Option positions SHALL be unique nonnegative integers per question. Their reordering SHALL follow the same complete-permutation rule as presentation reordering. Published option identity SHALL remain stable for future answers.

#### Scenario: Pairwise contract uses actual input identity later
- **WHEN** an author publishes a pairwise question targeting a two-item candidate slot
- **THEN** the contract records the slot reference rather than static options named A and B or dataset item IDs

#### Scenario: Impossible choice fails publication
- **WHEN** a version has a static choice with fewer than two options, a pairwise slot allowing three items, or selection bounds exceeding the guaranteed available choices
- **THEN** publication fails and the version remains an editable draft

#### Scenario: Blank option label is rejected
- **WHEN** an author creates or updates a static option with an empty or whitespace-only label
- **THEN** the write fails without persisting an unusable choice

#### Scenario: Static and dynamic options cannot be mixed
- **WHEN** an author adds a static option to an input-choice question or a slot reference to a static-choice question
- **THEN** the write is rejected

### Requirement: Version-owned annotation definitions
The system SHALL support version-owned label sets with ordered labels whose nonempty keys are unique within their set; set keys SHALL be unique within the version and label positions SHALL be unique nonnegative integers within the set. Each label SHALL have nonblank plain-text display text containing at least one non-whitespace character, enforced on creation and update. Annotation questions SHALL reference one required source field requirement and a nonempty label set from the same version. Bounding-box, polygon, and raster-mask definitions SHALL require an asset source with intended use `image`; text-span definitions SHALL require a text source. Annotation questions SHALL declare a nonnegative minimum and finite maximum region or span count with minimum no greater than maximum. Contracts SHALL describe bounding-box and polygon coordinates as normalized to the source image, masks as future immutable asset references requiring source dimensions, and text-span offsets as zero-based Unicode code-point offsets with an exclusive end. No coordinates, mask assets, spans, task-input identities, or response values SHALL be persisted by form authoring. Label reordering SHALL follow the complete-permutation rule. Changing a referenced source's family or intended use SHALL fail if it makes an existing question incompatible.

#### Scenario: Blank annotation label text is rejected
- **WHEN** an author creates or updates a label with empty or whitespace-only display text
- **THEN** the write fails without persisting an unusable annotation category

#### Scenario: Annotation source is validated structurally
- **WHEN** an author links a bounding-box question to a text requirement or to an asset requirement intended only for download
- **THEN** the write fails without claiming image compatibility

#### Scenario: Annotation definition remains reusable
- **WHEN** an author publishes a text-span question with a label set and a required text source
- **THEN** inspection returns the source requirement, labels, count bounds, and offset convention without any concrete text, task input, or answer

#### Scenario: Annotation definitions do not enable rendering
- **WHEN** a version containing image-choice or image-annotation questions is published
- **THEN** publication validates only the form contract and neither grants storage access nor changes opaque-download behavior; execution requires a later consumer and the separately scoped rendering prerequisites

### Requirement: Atomic publication freezes a complete contract
Publication SHALL require a nonblank version title containing at least one non-whitespace character, at least one input slot with at least one field requirement per slot, at least one question, exactly one placement per question, all required typed constraints and child records, valid same-version references, compatible types, feasible bounds, and unique keys and positions. Drafts SHALL permit incomplete graphs but SHALL never persist invalid local values or dangling references. Every write to version metadata or owned definitions, including additions, removals, reordering, and related-reference changes, SHALL serialize against publication of that version and revalidate draft state after acquiring the shared mutation boundary. Publication SHALL change the complete graph atomically from draft to published with a publication timestamp. A successful authorized retry of publication SHALL return the same published version without changing it. A failed validation SHALL leave the graph and state unchanged. Published versions and every owned definition SHALL reject update, deletion, ownership changes, and further child insertion through the supported Ash authoring actions. Lifecycle, immutable ownership, and subtype rules SHALL be implemented in Elixir using that transactional boundary, not database triggers or stored functions. Private persistence actions SHALL remain implementation steps inside these operations, not independently supported authoring APIs. Direct SQL, seeding, and privileged low-level persistence are outside this business-rule contract; ordinary foreign keys, uniqueness, nullability, and scalar checks SHALL remain in PostgreSQL.

#### Scenario: Incomplete draft can be repaired
- **WHEN** an author publishes a draft with an empty or whitespace-only title, an unplaced question, or an empty required option set or label set
- **THEN** publication returns sanitized validation issues identifying only definitions in the authorized version, and the author can repair and retry the draft

#### Scenario: Child edit races publication
- **WHEN** a definition edit and publication execute concurrently
- **THEN** either the complete edit commits before publication and is included in validation, or publication commits first and the edit fails because the version is published

#### Scenario: Published graph cannot change through an authoring action
- **WHEN** a caller attempts to insert, update, delete, or reparent a child of a published version through an Ash authoring action, including with a record loaded while the version was still a draft
- **THEN** the change is rejected and the published identities and content remain unchanged

#### Scenario: Concurrent publication converges
- **WHEN** two authorized publish requests target the same valid draft
- **THEN** they resolve to the same published version and publication timestamp with no duplicate version or partial graph

### Requirement: Bounded GraphQL authoring and inspection
The system SHALL expose form creation, empty or published-copy draft creation, draft metadata and definition editing, reordering, publication, and scoped inspection through GraphQL. Public lifecycle operations SHALL require explicit organization scope. Presentation mutations SHALL operate on element IDs and directly accept kind-specific content. Question creation and updates SHALL directly accept input-slot and source-requirement IDs. Typed constraints SHALL remain available through their owning question; standalone collection APIs for presentation subtypes, input sources, and constraints are not required. Lists of forms, versions, slots, requirements, elements, questions, options, label sets, and labels SHALL use stable cursor pagination with a default page size of 50 and maximum 100, including nested collections. Ordered collections SHALL paginate in authored position order with an identity tie-breaker. Queries SHALL enforce the existing query-complexity controls. Every integer exposed by the form contract SHALL fit GraphQL Int (−2,147,483,648 through 2,147,483,647), including text-length and annotation-count bounds, slot/selection counts, positions, and version numbers. Nonnegative or positive lower bounds and tighter domain limits SHALL still apply. Public and internal authoring paths SHALL reject out-of-range values before persistence; generated positions and version allocation SHALL fail atomically at exhaustion without wrapping or widening the scalar. Writes and publication SHALL enforce documented finite limits for total definitions, text sizes, option and label counts, and slot sizes; oversized requests SHALL fail without partial writes. Published inspection SHALL include version number, state, publication timestamp, typed constraints, and stable definition identities needed for future consumers. Internal unrestricted writes, storage locations, worker operations, and response mutations SHALL NOT be exposed.

#### Scenario: Later-page definitions remain accessible
- **WHEN** an authorized reader follows cursors through a published version with more than one page of options or elements
- **THEN** every definition is available in stable order without an unbounded nested expansion

#### Scenario: Oversized mutation is rejected
- **WHEN** a mutation exceeds a documented definition or payload limit
- **THEN** the system rejects it atomically with a sanitized validation error

#### Scenario: Constraint metadata fits GraphQL Int
- **WHEN** an author supplies a text-length or annotation-count bound of 2,147,483,648 through a direct authoring action
- **THEN** the write fails before persistence; 2,147,483,647 remains representable where no tighter domain limit applies

#### Scenario: Published inspection is a definition contract
- **WHEN** a reader inspects a published form through GraphQL
- **THEN** the response identifies its immutable typed definitions without creating projects, tasks, answers, or asset-access descriptors
