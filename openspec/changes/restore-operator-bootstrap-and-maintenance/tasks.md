## Status

**Future / deferred. These unchecked tasks are not the current execution queue.** Obtain an explicit decision to resume after further organization onboarding and storage progress.

## 1. Revalidate the design

- [ ] 1.1 Confirm the operator workflow, selected storage provider, operational scale, retention requirements, and current Oban capabilities; revise the specs and design before implementation.
- [ ] 1.2 Plan migrations and safe handling of accumulated credentials, staging, abandoned imports, and pending rows with missing job evidence.

## 2. Restore the selected capabilities

- [ ] 2.1 Implement operator setup and explicit grants through existing Ash primitives with atomic conflict handling and idempotency.
- [ ] 2.2 Implement bounded authentication retention independently of expiry and replay enforcement.
- [ ] 2.3 Implement safe staging retirement and publication reconciliation for the chosen provider.
- [ ] 2.4 Implement expired-open-import deletion while preserving sealed history and referenced records.
- [ ] 2.5 Implement terminal import-row recovery and coordinate backlog capacity with evidence retention and pruning.

## 3. Verify and document

- [ ] 3.1 Add the meaningful concurrency, lifecycle, and provider-contract coverage described in the design; document operator commands and actual schedules.
- [ ] 3.2 Run `mise run verify`, independent review, and `mise run openspec.validate`; synchronize the restored active specifications.
