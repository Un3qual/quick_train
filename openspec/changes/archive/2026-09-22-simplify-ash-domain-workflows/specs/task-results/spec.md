## ADDED Requirements

### Requirement: Resume completed export byte publication
An export retry whose owned asset has already published immutable bytes SHALL resume integrity verification, access issuance, and export readiness without rereading and re-encoding the sealed result set. It SHALL preserve canonical ownership, hash/size/media facts, snapshot membership, and sanitized failures. Missing or unusable unpublished assets SHALL retain existing regeneration/replacement behavior.

#### Scenario: Access issuance fails after publication
- **WHEN** export bytes are ready but issuing access fails
- **THEN** retry verifies and exposes the same owned bytes without creating another complete export file
