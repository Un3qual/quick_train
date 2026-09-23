## ADDED Requirements

### Requirement: Bounded provider metadata failures
Provider discovery and key retrieval SHALL complete or fail within the metadata caller deadline. Metadata timeouts and cache unavailability SHALL return the existing sanitized provider-unavailable error and discard any pending login created for that failed begin operation. Secure endpoint validation and stale-metadata rejection SHALL remain unchanged.

#### Scenario: Metadata retrieval times out
- **WHEN** metadata cannot be obtained within the configured request deadline
- **THEN** login begin returns a sanitized provider error and discards its pending login rather than exiting the caller
