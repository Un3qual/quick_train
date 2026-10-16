## MODIFIED Requirements

### Requirement: Finalization seals the accepted row set
Every import SHALL begin in persisted phase `open` with a server-calculated immutable expiry. Append and finalization SHALL lock the same import and recheck its phase and expiry. The first valid finalization SHALL atomically change the phase to `sealed` and insert one durable bounded-retry import processing job if any pending row exists; failure to insert that job SHALL roll back sealing. Sealing an import with no pending rows SHALL create no processing job. A sealed import SHALL accept no later row. An expired open import SHALL reject append and first finalization with `import_expired`. Matching sequential or concurrent finalization retries SHALL return the same sealed import and SHALL not enqueue duplicate processing.

#### Scenario: Append races finalization
- **WHEN** finalization seals the import before a concurrent append acquires its lock
- **THEN** the append fails with `import_not_open` and adds no row

#### Scenario: Lost finalization response is retry safe
- **WHEN** finalization with pending rows commits but its response is lost
- **THEN** a retry returns the sealed import and one import processing job covers the remaining pending rows

#### Scenario: Expired open import rejects work
- **WHEN** append or first finalization locks an open import after its expiry
- **THEN** it fails with `import_expired` and creates no row or processing job

#### Scenario: No pending rows require no worker
- **WHEN** an empty import or one containing only terminal failed rows is sealed
- **THEN** no processing job is inserted and derived progress reports the existing row outcomes

### Requirement: Row processing is idempotent and retryable
The import processing job SHALL page the sealed import's pending rows in bounded keyset reads ordered by immutable row identity rather than materialize the complete import or create one job per row. Each row SHALL retain its existing independent transaction: lock the row, return without changes if already terminal, and atomically commit its item revision reference and terminal succeeded, unchanged or failed outcome. Expected permanent row-validation failures SHALL record a sanitized terminal failed outcome and allow processing of other rows. Transient infrastructure failures SHALL leave the current row pending for bounded job retry; they SHALL NOT be misreported as invalid source input. Retry SHALL start a new keyset traversal of remaining pending rows rather than resume a persisted cursor, and SHALL NOT duplicate committed revisions or repeat terminal rows. Successful completion SHALL require no pending rows.

An unexpected exception or otherwise unclassified processing failure SHALL roll back the current row and fail the import job through ordinary Oban error handling; it SHALL NOT become a terminal source-validation failure or be swallowed to report success. One bounded Oban attempt budget SHALL cover the entire import. Committed row progress SHALL NOT reset that budget. Per-row retry counters and automatic attempt resets SHALL NOT be introduced.

Automatic terminal-job recovery remains deferred to restore-operator-bootstrap-and-maintenance. A discarded or cancelled import job may leave pending rows; derived progress SHALL report them honestly rather than invent completion. Job pruning is not coordinated with that deferred recovery. No separate progress counters, row-job fan-out or generic chunk-processing lifecycle SHALL be added.

#### Scenario: Row-job scheduling is atomic with sealing
- **WHEN** finalization cannot insert the import processing job
- **THEN** sealing rolls back and an identical retry can perform the same operation without leaving pending rows with no durable processing request

#### Scenario: Row worker fails before commit
- **WHEN** an import job commits several row outcomes and then fails before the next row transaction commits
- **THEN** retry processes only remaining pending rows and creates no duplicate item revision

#### Scenario: One row is permanently invalid
- **WHEN** row processing identifies an expected permanent validation failure
- **THEN** it records that row's sanitized failure and continues other rows without failing the entire import

#### Scenario: Infrastructure fails
- **WHEN** a database or storage dependency fails transiently during a row transaction
- **THEN** the row remains pending and standard bounded job retry can resume without manufacturing a source-validation failure

#### Scenario: An unexpected row failure repeats
- **WHEN** earlier row outcomes have committed and a later row repeatedly raises an unexpected internal exception
- **THEN** that row's transaction rolls back and the import job fails and retries within its shared attempt budget, preserving committed rows without reporting a source-validation failure
- **AND** later rows may remain pending until the cause is fixed and processing recovers; the import is not reported complete

#### Scenario: Terminal rows do not shift later pages
- **WHEN** processing makes an earlier page terminal before reading the next page of pending rows
- **THEN** keyset traversal reaches the remaining rows without offset-based skips, and a retry restarts from remaining pending rows rather than its previous execution's cursor

#### Scenario: Progress does not reset the import retry budget
- **WHEN** successive import-job executions commit row progress but encounter transient failures on different later rows
- **THEN** each failed execution consumes the same bounded import-wide attempt budget, and exhaustion preserves committed outcomes while leaving unfinished rows pending

#### Scenario: Retry exhaustion leaves unresolved progress visible
- **WHEN** the import job exhausts its attempts or is cancelled before all rows are terminal
- **THEN** remaining rows stay pending until explicit recovery, while previously committed row outcomes remain intact

#### Scenario: Concurrent finalization spans multiple job batches
- **WHEN** concurrent callers finalize an import with more pending rows than a processing page
- **THEN** one sealed import and one import processing job commit, independent of the number of row pages

#### Scenario: Row worker loses success acknowledgement
- **WHEN** a row transaction commits and the import job retries before recording success
- **THEN** the terminal row is skipped and no duplicate revision is created
