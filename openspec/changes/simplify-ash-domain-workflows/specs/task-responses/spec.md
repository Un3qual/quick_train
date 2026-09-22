## ADDED Requirements

### Requirement: Accurate attempt permission checks
Attempt action permission checks SHALL reject absent, inactive, non-owner, or currently ineligible actors within the explicit organization/project scope. Eligible external workers SHALL not require organization membership. Execution SHALL still recheck current ownership, eligibility, lifecycle, and applicable lease rules after acquiring owner locks, preserving terminal retry and receipt behavior.

#### Scenario: Another worker checks submission permission
- **WHEN** an active worker checks permission to submit another worker's attempt
- **THEN** permission is denied before action execution

### Requirement: Submission-local source validation
Submission SHALL hydrate and measure each distinct referenced text source once per submission while checking every answer's requirement binding, input/source provenance, organization/schema scope, and codepoint boundaries. Final lease validation SHALL remain inside the locked submission workflow.

#### Scenario: Several span questions share one source
- **WHEN** submitted answers reference the same immutable source through several questions
- **THEN** source loading and length calculation are shared while each question retains its own binding and span checks
