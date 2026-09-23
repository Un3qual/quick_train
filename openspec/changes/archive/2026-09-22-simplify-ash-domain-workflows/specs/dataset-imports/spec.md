## ADDED Requirements

### Requirement: Native idempotent import opening
Import opening SHALL expose a native create mutation with a result/errors envelope. A repeated organization/dataset/key request SHALL return its original import only when requester and schema fingerprint match, preserving original expiry and attribution.

#### Scenario: Open retry preserves original facts
- **WHEN** an authorized caller repeats an identical import-open request
- **THEN** the existing import is returned without extending its expiry or changing its initiator
