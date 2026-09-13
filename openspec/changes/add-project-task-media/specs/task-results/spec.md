## MODIFIED Requirements

### Requirement: Exports stream and publish atomically
Exports SHALL produce format-versioned JSONL with one header and one line per selected evidence row ordered by kind then immutable ID. Evidence kinds SHALL be `task`, `task_input`, `attempt`, `attempt_question`, `attempt_input_presentation`, `question_response`, `static_option_answer`, `task_input_answer`, `text_span`, `review_decision`, `presentation_element`, `question_definition`, `question_option`, `label`, `project_input_binding`, `dataset_value`, `bounding_box`, `polygon_region`, `polygon_point`, and `mask_region`. Spatial kinds SHALL use the existing evidence-kind/ID-range filters and count each region and polygon point separately. New image exports SHALL use an incremented format version while existing sealed export bytes remain unchanged. Rows SHALL retain exact owner/provenance IDs and authored/presentation/review order fields as applicable; related collections SHALL be separate records rather than nested expansions. Shared evidence SHALL be deduplicated by kind/ID. Decimals SHALL retain exact precision and hashes SHALL use lowercase hexadecimal. Persistence of project/answer content SHALL remain relational; JSONL is only the output format. Export counts SHALL include every selected evidence row, including typed children, decisions, and shared context, and SHALL serialize as exact nonnegative decimal strings. This change SHALL impose no export record-count or output-byte ceiling. Existing Assets/provider publication constraints SHALL still apply; a publication failure SHALL expose no downloadable partial artifact. Callers SHALL be able to narrow both task and evidence ranges. Generation SHALL stream records using paged reads and temporary-file cleanup and publish one verified immutable organization asset only after the entire artifact succeeds.

#### Scenario: Asset publication fails
- **WHEN** export publication fails under the configured Assets/provider contract
- **THEN** it returns a sanitized failure with no ready download or partially published artifact

#### Scenario: An export contains many child records
- **WHEN** selected outcomes include extensive typed children and review history
- **THEN** generation streams every selected record from the sealed snapshot without truncating the evidence or imposing an export-specific count limit

#### Scenario: The output contains a precise decimal
- **WHEN** an exported answer is a decimal
- **THEN** JSONL represents it as an exact string rather than an imprecise binary floating-point number

#### Scenario: Spatial evidence is partitioned within one outcome
- **WHEN** a caller selects polygon-point evidence within a bounded ID range
- **THEN** only the selected point records are emitted with their region/outcome/source provenance IDs, without implicitly expanding all sibling regions, points, or review history
