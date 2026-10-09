## ADDED Requirements

### Requirement: Questions declare peer reputation participation
Each question SHALL have one boolean declaring whether its answers may participate in peer reputation scoring, defaulting to true when omitted. Explicit null or nonboolean authoring values SHALL be rejected. An authorized author SHALL be able to set or change this value only while the owning form version is draft, through the existing explicitly organization-scoped Forms authoring operations requiring an active account, active organization, active membership and `forms.manage`. Possession of `projects.manage` alone SHALL NOT grant question-authoring authority. Foreign and nonexistent targets SHALL fail without distinguishable disclosure. Inspection SHALL retain the existing general `forms.read` and attempt-owned published-contract access rules without granting additional source access.

Copying a published form version SHALL preserve each question's authored value in the new draft. Question edits SHALL share the existing form-version mutation/publication boundary and recheck draft state after lock waits. Publication SHALL freeze this value with the rest of the owned question graph. Changing participation for future work SHALL require editing a draft and publishing a new form version; existing published versions and projects pinned to them SHALL retain their values. Existing questions SHALL retain included behavior through the additive default rather than acquire a retroactive exclusion. This value SHALL NOT designate a known-answer check, alter answer validation or collection, enable unsupported matching, or introduce question weights or per-project question overrides.

#### Scenario: An author excludes a preference question
- **WHEN** an authorized form author sets a draft preference question's peer-participation value to false and publishes the version
- **THEN** the published contract retains that exclusion while another question left at its default remains included

#### Scenario: A published contract is copied
- **WHEN** an authorized author copies a published form version containing both included and excluded questions
- **THEN** the new draft preserves those values, and editing the draft changes neither the source version nor projects pinned to it

#### Scenario: A question edit waits behind publication
- **WHEN** a participation edit obtains the form-version mutation boundary after publication commits
- **THEN** the edit is rejected and the published value remains unchanged

#### Scenario: Project management does not authorize form edits
- **WHEN** an actor lacks the owning organization's active membership or `forms.manage`, even if they can manage a project
- **THEN** the participation mutation is denied without modifying or disclosing an unauthorized question

#### Scenario: Invalid participation input fails atomically
- **WHEN** an otherwise authorized draft mutation supplies an explicit null or nonboolean value
- **THEN** validation fails without changing the question, while an omitted value on creation resolves to true
