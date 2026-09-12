## REMOVED Requirements

### Requirement: Bounded GraphQL query work
**Reason**: GraphQL complexity accounting and enforcement are deferred for the initial MVP.
**Migration**: Remove the shared HTTP complexity budget and Forms/Datasets collection-cost callbacks. Existing authorization, bounded pagination, request-body limits, and domain-specific write limits remain in force; clients need no API changes.
