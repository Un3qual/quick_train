## ADDED Requirements

### Requirement: Native form copy and publication contracts
Published-form copying SHALL expose a native create mutation; form publication SHALL expose a native update mutation. Both SHALL use typed inputs and result/errors envelopes and generated domain interfaces. Organization scope, manager authority, parent locks, complete graph validation, atomic copy rollback, and publication retry timestamps SHALL be preserved.

#### Scenario: Repeated publication
- **WHEN** an authorized manager publishes an already-published version
- **THEN** the same version and original publication timestamp are returned
