# Spec: Postal.Function — TypeScript / Node.js Reimplementation

Version 1.2, 2026-11-10

**Corrections from .NET source review (v1.2):**
- `FlushBatchAsync` now performs bulk insert + `RowsWritten` update in one SQL transaction (fixed in .NET). TS must keep the atomic behavior.
- `FinalizeImportAsync` wraps `EXEC Postalweb` + `EXEC Postalwebboth` + `Succeeded` status in one SQL transaction. The current `Run()` path still calls three separate methods (each opens its own connection) — **TS should use the `FinalizeImportAsync` pattern** (single transaction).
- Progress statuses are free-text exactly as emitted (7 steps). Preserve for UI.
- Parser throws on invalid integers; skips whitespace/null records; warns+skips short lines; throws on long lines; binary trailing partial warns and stops.
- Startup log is `LogError` in .NET (change to Information in TS). Full blob URI is logged in .NET (sanitize to container + name only in TS).
- `totalRecords = SizeBytes / 309` is approximation only (used in error messages).
- Queue client uses `AzureWebJobsStorage` connection string. Visibility renewal passes original message text and tracks new `popReceipt`.
- `POSTAL_IMPORTS_CONTAINER` has a two-level fallback: `POSTAL_IMPORTS_CONTAINER` → `IMPORTS_CONTAINER` → `"imports"`.
- `POSTAL_MANAGED_IDENTITY_CLIENT_ID` has a three-level fallback: `POSTAL_MANAGED_IDENTITY_CLIENT_ID` → `AZURE_CLIENT_ID` → `MANAGED_IDENTITY_CLIENT_ID`.
- `TRUNCATE TABLE` is DDL and auto-commits in SQL Server — it cannot be wrapped in a transaction.

## 1. Purpose & Scope

Identical file-to-database behavior to `ImportWorker.cs`:
- Queue-triggered (`imports`) worker.
- Fixed-width 309-byte ASCII WRK parser (text or binary mode via 8192-byte sniff).
- `TRUNCATE Delstat` only when `RowsWritten == 0`; otherwise resume from checkpoint.
- Batched bulk insert into `Delstat` + checkpoint in one transaction.
- Sequential `EXEC Postalweb` then `EXEC Postalwebboth`.
- `ImportJob` claim (CAS), progress statuses, error handling, max retries.
- Visibility renewal loop.
- Managed identity (Blob, SQL) with connection-string fallback.

**Out of scope:** Postal.Api, postal-web, schema, stored procedures, Bicep.

**Known .NET behaviors to preserve or fix:**
- Status strings must match exactly (UI polling).
- Startup log → Information (not Error).
- Blob logs: container + blob name only (no storage account URL).
- Atomic bulk + checkpoint (single transaction, already true in .NET).
- Atomic finalization: `EXEC Postalweb` + `EXEC Postalwebboth` + `Succeeded` status in one transaction (use `FinalizeImportAsync` pattern).
- Sanitized SQL config summary at startup (DataSource, InitialCatalog, auth mode — no passwords).
- Structured logging scope with `jobId`, `dequeueCount`, `queueMessageId` for App Insights correlation.

## 2. Definitions

| Term | Definition |
|------|------------|
| **WRK file** | Fixed-width ASCII file; each record is exactly 309 bytes. Record type `D` = data row, `C` = control (skipped). |
| **Delstat** | Target SQL table receiving parsed rows via bulk insert. Truncated before a fresh import. |
| **ImportJob** | Row in the `ImportJob` table tracking one import: `Id` (GUID), `BlobName`, `OriginalFileName`, `SizeBytes`, `Status`, `RowsWritten`, `Error`, `CreatedUtc`, `CompletedUtc`. |
| **CAS claim** | Compare-and-swap job claim: `UPDATE ImportJob SET Status='Running' WHERE Id=@Id AND Status LIKE 'Queued%'`. Returns 1 row if claimed, 0 if another worker owns it. |
| **Visibility renewal** | Periodic `UpdateMessage` call to extend the queue message's visibility timeout while processing, preventing re-delivery. |
| **Checkpoint** | `RowsWritten` counter incremented per batch; on resume, records at or below this count are skipped. |
| **Sniff** | Reading the first 8 192 bytes of the blob to detect whether the file uses CRLF line endings (text mode) or is raw fixed-width (binary mode). |
| **B1 plan** | The shared dedicated App Service plan (`Standard_B1`) hosting both `postal-api` and `postal-worker`. Supports `NODE\|20` runtime. |
| **Processing step status** | `"Processing Step {n}/7 - {detail}"` (n=1..7). |
| **Retry status** | `"QueuedForRetry {dequeueCount}"`. |
| **Error suffix** | `"{ex.message} \| RowsWritten={n}"`. |

## 3. Requirements, Constraints & Guidelines

### 3.1 Functional Requirements

- **REQ-001:** The function SHALL trigger on the `imports` Azure Storage queue, receiving a base64-encoded message containing a GUID `jobId`.
- **REQ-002:** The function SHALL parse the `jobId` from the queue message. If the message is not a valid GUID, log an error and return without rethrowing (poison message — do not retry). GUID parse trims surrounding quotes.
- **REQ-003:** The function SHALL enforce a maximum dequeue count (`maxDequeueCount = 6`). If `dequeueCount > maxRetries` (default 5), mark the job `Failed` with error `"Exceeded max retries (N)."` and return without rethrowing. Check occurs before claim.
- **REQ-004:** The function SHALL perform a CAS claim on the `ImportJob` row before processing. If the claim fails (0 rows updated), log a warning and return.
- **REQ-005:** If `RowsWritten == 0`, the function SHALL execute `TRUNCATE TABLE Delstat` before importing. If `RowsWritten > 0`, the function SHALL resume from the checkpoint (skip records at or below `RowsWritten`).
- **REQ-006:** The function SHALL open the blob identified by `ImportJob.BlobName` in the `POSTAL_IMPORTS_CONTAINER` container. If the blob does not exist, throw an error containing `"Blob not found"` (triggers retry).
- **REQ-007:** The function SHALL sniff the first 8 192 bytes of the blob stream for `\r` or `\n` characters to determine parse mode:
  - **Text mode** (newline found): read line-by-line; each line must be exactly 309 characters.
  - **Binary mode** (no newline): read fixed 309-byte chunks.
- **REQ-008:** The function SHALL parse each 309-byte record as follows:
  - Byte 0: record type (`D` = data, `C` = control/skip, anything else = error)
  - Bytes 1–5: `zipcode` (string, trimmed)
  - Bytes 17–20: `routeid` (string, trimmed)
  - 16 integer fields at fixed offsets (see §4.3)
  - Whitespace-only / null / empty lines: skip (not counted).
  - Text short line (<309): warn + skip.
  - Text wrong length (!=309): throw `InvalidDataException` with lengths + counters.
  - Type `C`: skip (not counted in `RowsWritten`).
  - Type not `D`/`C`: throw with type char + counters.
  - Binary trailing partial (<309): warn + ignore remainder.
  - Integer fields: `int` parse after trim; throw `InvalidDataException` on failure (include field name + raw value).
- **REQ-009:** The function SHALL batch parsed rows and bulk-insert into `Delstat` when the batch reaches `POSTAL_IMPORT_BATCH_SIZE` (default 1 000, range 1–50 000).
- **REQ-010:** After each batch insert, the function SHALL increment `ImportJob.RowsWritten` by the batch size. **The bulk insert and the `RowsWritten` increment MUST execute within the same SQL transaction**.
- **REQ-011:** After all records are processed, the function SHALL execute `EXEC Postalweb` followed by `EXEC Postalwebboth`, then mark the job `Succeeded` (with `CompletedUtc = UTC now`). **All three operations MUST execute within the same SQL transaction** (use the `FinalizeImportAsync` pattern from .NET).
- **REQ-012:** The function SHALL mark the job `Failed` (with error message and `CompletedUtc = UTC now`) if an unhandled exception occurs and `dequeueCount >= maxRetries`.
- **REQ-013:** If an exception occurs and `dequeueCount < maxRetries`, the function SHALL set status to `"QueuedForRetry {dequeueCount}"` and rethrow to trigger Azure Functions retry.
- **REQ-014:** The function SHALL run a visibility renewal loop that calls `UpdateMessage` every `POSTAL_QUEUE_VISIBILITY_RENEWAL_SECONDS` (default 120 s) with a timeout of `POSTAL_QUEUE_VISIBILITY_TIMEOUT_SECONDS` (default 600 s), until processing completes or is cancelled. Pass original message text; update local `popReceipt` from response.
- **REQ-015:** If the `ImportJob` row is not found in the database (0 rows returned by `GetImportJob`), the function SHALL log an error and return without rethrowing (no retry — the job was likely deleted or the GUID is wrong).

**Progress statuses (exact strings):**
1. `"Processing Step 1/7 - Started"`
2. `"Processing Step 2/7 - Preparing destination table"` or `"Processing Step 2/7 - Resuming import from row {N}"`
3. `"Processing Step 3/7 - WRK file found"`
4. `"Processing Step 4/7 - Importing WRK records"`
5. `"Processing Step 5/7 - Running Postalweb"`
6. `"Processing Step 6/7 - Running Postalwebboth"`
7. `"Processing Step 7/7 - Finalizing import job"`

Then `"Succeeded"` (with `CompletedUtc`).

`totalRecords ≈ SizeBytes / 309` used only in exception messages.

### 3.2 Non-Functional Requirements

- **NFR-001:** The function SHALL support files up to 10 GB (matching the `Postal.Api` upload cap) by streaming (never load full file into memory).
- **NFR-002:** The function SHALL use managed identity for all Azure service authentication (Blob, Queue, SQL). A connection-string fallback (`POSTAL_DB_CONN`) SHALL be supported for local development. SQL token scope: `https://database.windows.net/.default`. Encrypt=true, TrustServerCertificate=false.
- **NFR-003:** The function SHALL log at `Information` level for normal operations and `Error` level for failures. Log messages SHALL include `jobId` for correlation. Startup log is Information (not Error). Blob logs contain container + name only.
- **NFR-004:** The function SHALL be deployable to the existing B1 App Service plan with runtime stack `NODE|20`.

### 3.3 Constraints

- **CON-001:** The function MUST NOT modify the `ImportJob` schema, `Delstat` schema, or the `Postalweb` / `Postalwebboth` stored procedures.
- **CON-002:** The function MUST NOT change the queue name, blob container name, or message format. The .NET `Postal.Api` enqueues base64-encoded GUID strings; the TypeScript worker must consume the same format.
- **CON-003:** The function MUST use the `mssql` npm package (TDS protocol) for SQL access. `SqlBulkCopy` equivalent is `request.bulk()`.
- **CON-004:** The Node.js blob download stream is **not seekable**. The sniff step MUST buffer the first 8 192 bytes before deciding parse mode, then re-emit those bytes into the parse pipeline.
- **CON-005:** The function MUST run on Node.js 20 LTS (matching `NODE|20` runtime stack on the B1 plan).

### 3.4 Guidelines

- **GUD-001:** Use TypeScript strict mode. All functions SHALL have explicit return types.
- **GUD-002:** Use `AbortController` / `AbortSignal` for cancellation propagation (equivalent to .NET `CancellationToken`).
- **GUD-003:** Structure the code as a single `src/` directory with focused modules (see §4.1). Avoid a single monolithic file.
- **GUD-004:** All SQL queries SHALL use parameterized statements. No string concatenation of user input into SQL.
- **GUD-005:** Environment variable names SHALL match the .NET implementation exactly (see §5) to allow side-by-side deployment without configuration changes.

## 4. Interfaces & Data Contracts

### 4.1 Project Structure

```
src/Postal.Function/
├── package.json          # @azure/functions ^4, @azure/identity, @azure/storage-blob, @azure/storage-queue, mssql, typescript
├── tsconfig.json         # strict, target ES2022, module NodeNext
├── host.json
├── local.settings.json
├── src/
│   ├── index.ts          # Queue trigger entry
│   ├── config.ts
│   ├── credential.ts
│   ├── sql.ts            # pool + transaction helper
│   ├── blob.ts           # download + sniff + re-emit
│   ├── parser.ts         # 309-byte parser + validation
│   ├── bulkInsert.ts     # bulk + checkpoint (single txn)
│   ├── jobRepo.ts
│   ├── visibility.ts
│   └── types.ts
└── test/
    ├── parser.test.ts
    ├── bulkInsert.test.ts
    ├── jobRepo.test.ts
    └── visibility.test.ts
```

### 4.2 Queue Message Contract

The .NET `Postal.Api` enqueues a **base64-encoded GUID string** to the `imports` queue. The TypeScript worker receives the same format. Functions host (`messageEncoding: base64`) delivers decoded UTF-8 GUID string + `dequeueCount`, `id`, `popReceipt`.

| Field | Type | Description |
|-------|------|-------------|
| `message` | `string` | Decoded UTF-8 GUID string. |
| `dequeueCount` | `number` | Number of times this message has been dequeued (1-based). |
| `id` | `string` | Queue message ID (for visibility renewal). |
| `popReceipt` | `string` | Pop receipt (for visibility renewal). |

If the string is not a valid GUID, log an error and return (poison message, REQ-002).

### 4.3 WRK Record Field Map (309 bytes)

All offsets are 0-based byte positions in the ASCII-encoded record.

| Offset | Length | Column | Type | Notes |
|--------|--------|--------|------|-------|
| 0 | 1 | — | char | Record type: `D` = data, `C` = control (skip) |
| 1 | 5 | `zipcode` | string | Trimmed |
| 6 | 11 | — | — | Reserved / unused |
| 17 | 4 | `routeid` | string | Trimmed |
| 21 | 5 | `actBcentral` | int | |
| 26 | 5 | `actBcurb` | int | |
| 31 | 5 | `actBndcbu` | int | |
| 36 | 5 | `actBother` | int | |
| 41 | 5 | `actBfacility` | int | |
| 46 | 5 | `actBcontract` | int | |
| 51 | 5 | `actBdetached` | int | |
| 56 | 5 | `actBnpu` | int | |
| 61 | 20 | — | — | Reserved / unused |
| 81 | 5 | `actRcentral` | int | |
| 86 | 5 | `actRcurb` | int | |
| 91 | 5 | `actRndcbu` | int | |
| 96 | 5 | `actRother` | int | |
| 101 | 5 | `actRfacility` | int | |
| 106 | 5 | `actRcontract` | int | |
| 111 | 5 | `actRdetached` | int | |
| 116 | 5 | `actRnpu` | int | |
| 121 | 188 | — | — | Reserved / unused (pads to 309) |

**Total:** 309 bytes per record. 18 columns total.

### 4.4 SQL Operations

All operations use parameterized queries via the `mssql` package.

| Operation | SQL | Parameters |
|-----------|-----|------------|
| Get job | `SELECT BlobName, Status, RowsWritten, SizeBytes, Error FROM ImportJob WHERE Id = @Id` | `@Id` (uniqueidentifier) |
| CAS claim | `UPDATE ImportJob SET Status = 'Running', Error = NULL WHERE Id = @Id AND Status LIKE 'Queued%'` | `@Id` (uniqueidentifier) |
| Truncate | `TRUNCATE TABLE Delstat` | — |
| Bulk + checkpoint | Single transaction: `bulk()` into Delstat + `UPDATE ImportJob SET RowsWritten = RowsWritten + @Added WHERE Id = @Id` | 18 columns per row; `@Added` (int), `@Id` |
| Finalize (single txn) | `EXEC Postalweb` + `EXEC Postalwebboth` + `UPDATE ImportJob SET Status='Succeeded', CompletedUtc=@Now WHERE Id=@Id` | `@Now` (datetime2), `@Id` |
| Progress / status | `UPDATE ImportJob SET Status = @Status, Error = COALESCE(@Error, Error), CompletedUtc = CASE WHEN @IsTerminal = 1 THEN @Now ELSE CompletedUtc END WHERE Id = @Id` | `@Status`, `@Error`, `@IsTerminal`, `@Now`, `@Id` |

> **Note:** `TRUNCATE TABLE` is DDL and auto-commits in SQL Server. It cannot be wrapped in a transaction. Execute it as a standalone statement before the first batch.

**`mssql` column types for `Delstat` bulk insert:**

| Column | `mssql` type |
|--------|-------------|
| `zipcode` | `mssql.NVarChar` |
| `routeid` | `mssql.NVarChar` |
| `actBcentral` … `actRnpu` (16 fields) | `mssql.Int` |

**Transaction requirement (REQ-010):**

```typescript
await pool.request().transaction(async (txn) => {
  const bulk = new BulkInsert(txn, "Delstat", columns);
  for (const row of batch) bulk.row(...row);
  await bulk.execute();

  await txn
    .input("Added", mssql.Int, batch.length)
    .input("Id", mssql.UniqueIdentifier, jobId)
    .query("UPDATE ImportJob SET RowsWritten = RowsWritten + @Added WHERE Id = @Id");
});
```

### 4.5 Blob Stream Handling (Non-Seekable)

```typescript
const download = await blobClient.download(0);
const stream = download.readableStreamBody!;
const sniff = Buffer.alloc(8192);
const sniffLen = await readExactly(stream, sniff, 8192);
const hasNewline = sniff.subarray(0, sniffLen).some(b => b === 0x0a || b === 0x0d);
const combined = new PassThrough();
combined.end(sniff.subarray(0, sniffLen));
stream.pipe(combined);  // remainder
// parse combined
```

### 4.6 Blob URI Construction

```typescript
function buildBlobUri(storageAccountUrl: string, container: string, blobName: string): string {
  const base = storageAccountUrl.replace(/\/$/, "");
  const cont = container.replace(/^\/|\/$/g, "");
  let rel = blobName.replace(/^\//, "");
  if (rel.toLowerCase().startsWith(cont.toLowerCase() + "/")) {
    rel = rel.slice(cont.length + 1);
  }
  return `${base}/${cont}/${rel}`;
}
```

Log only `container` + `blobName` (or sanitized relative path).

## 5. Configuration

### 5.1 Environment Variables

All variable names match the .NET implementation exactly (GUD-005).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STORAGE_ACCOUNT_URL` | **Yes** | — | Blob service URL, e.g. `https://syntaxstoragev2.blob.core.windows.net` |
| `POSTAL_IMPORTS_CONTAINER` | No | `imports` | Blob container for uploaded `.wrk` files. Fallback chain: `POSTAL_IMPORTS_CONTAINER` → `IMPORTS_CONTAINER` → `"imports"`. |
| `POSTAL_IMPORTS_QUEUE` | No | `imports` | Queue name for import job messages. |
| `POSTAL_DB_CONN` | No* | — | Full SQL connection string (local dev fallback). If set, used instead of managed identity. |
| `POSTAL_SQL_SERVER` | No* | — | SQL server hostname (managed identity path). *Required if `POSTAL_DB_CONN` is not set. |
| `POSTAL_SQL_DATABASE` | No* | — | SQL database name (managed identity path). *Required if `POSTAL_DB_CONN` is not set. |
| `POSTAL_USE_MANAGED_IDENTITY` | No | `true` | Set to `0`/`false`/`no` to disable managed identity (use `POSTAL_DB_CONN`). |
| `POSTAL_MANAGED_IDENTITY_CLIENT_ID` | No | — | User-assigned MI client ID. Fallback chain: `POSTAL_MANAGED_IDENTITY_CLIENT_ID` → `AZURE_CLIENT_ID` → `MANAGED_IDENTITY_CLIENT_ID`. If all absent, uses system-assigned MI. |
| `POSTAL_IMPORT_BATCH_SIZE` | No | `1000` | Rows per bulk insert batch. Range: 1–50 000. |
| `POSTAL_MAX_RETRIES` | No | `5` | Max dequeue count before marking job Failed. Range: 1–20. |
| `POSTAL_QUEUE_VISIBILITY_TIMEOUT_SECONDS` | No | `600` | Visibility timeout for renewal. Range: 60–7200. |
| `POSTAL_QUEUE_VISIBILITY_RENEWAL_SECONDS` | No | `120` | Interval between renewal calls. Range: 15–1800. |
| `AzureWebJobsStorage` | **Yes** | — | Storage connection string for the Functions host (queue trigger binding). Set by App Service. |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | No | — | App Insights connection string for telemetry. |

**Validation (at startup, in `config.ts`):**
- `STORAGE_ACCOUNT_URL` must be present and a valid `https://` URL.
- Either `POSTAL_DB_CONN` OR both `POSTAL_SQL_SERVER` + `POSTAL_SQL_DATABASE` must be set.
- All numeric values must be within their stated ranges.
- If validation fails, throw at module load (function will not start).

### 5.2 host.json

```json
{
  "version": "2.0",
  "extensions": {
    "queues": {
      "maxDequeueCount": 6,
      "visibilityTimeout": "00:10:00",
      "messageEncoding": "base64"
    }
  },
  "logging": {
    "fileLoggingMode": "always",
    "logLevel": {
      "default": "Information",
      "function": "Information",
      "Azure": "Warning",
      "Azure.Core": "Warning",
      "Azure.Identity": "Warning",
      "Microsoft.Identity": "Warning",
      "System.Net.Http.HttpClient": "Warning"
    }
  }
}
```

### 5.3 local.settings.json (development only — never commit)

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "STORAGE_ACCOUNT_URL": "https://<account>.blob.core.windows.net",
    "POSTAL_DB_CONN": "Server=tcp:<server>.database.windows.net,1433;Database=Postal;User ID=<user>;Password=<pwd>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;",
    "POSTAL_USE_MANAGED_IDENTITY": "false",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "FUNCTIONS_EXTENSION_VERSION": "~4"
  }
}
```

## 6. Acceptance Criteria

- **AC-001:** Given a valid GUID `jobId` in the queue message, When the function triggers, Then it SHALL log `"ImportWorker triggered"` at Information level with the `jobId` and `dequeueCount`.
- **AC-002:** Given a queue message that is not a valid GUID, When the function triggers, Then it SHALL log an error containing the raw message and return without throwing (no retry).
- **AC-003:** Given `dequeueCount > POSTAL_MAX_RETRIES`, When the function triggers, Then it SHALL mark the job `Failed` with error `"Exceeded max retries (N)."` and return without throwing.
- **AC-004:** Given an `ImportJob` row with `Status = 'Queued'`, When the CAS claim executes, Then the row SHALL be updated to `Status = 'Running'` and the function SHALL proceed.
- **AC-005:** Given an `ImportJob` row with `Status = 'Running'` (already claimed by another worker), When the CAS claim executes, Then 0 rows SHALL be updated and the function SHALL log a warning and return.
- **AC-006:** Given `RowsWritten = 0`, When processing begins, Then `TRUNCATE TABLE Delstat` SHALL execute before any rows are inserted.
- **AC-007:** Given `RowsWritten = 5000`, When processing begins, Then the first 5 000 data records SHALL be skipped (not inserted) and import SHALL resume from record 5 001.
- **AC-008:** Given a blob that does not exist at the expected URI, When the function attempts to open it, Then it SHALL throw an error containing `"Blob not found"` (triggers retry).
- **AC-009:** Given a WRK file with CRLF line endings, When the sniff detects a newline in the first 8 192 bytes, Then the parser SHALL operate in text mode (line-by-line, 309 chars per line).
- **AC-010:** Given a WRK file with no line endings (raw binary), When the sniff finds no `\r` or `\n` in the first 8 192 bytes, Then the parser SHALL operate in binary mode (fixed 309-byte chunks).
- **AC-011:** Given a record with type byte `C`, When the parser encounters it, Then the record SHALL be skipped (not inserted, not counted in `RowsWritten`).
- **AC-012:** Given a record with type byte other than `D` or `C`, When the parser encounters it, Then it SHALL throw an `InvalidDataException` containing the invalid type character.
- **AC-013:** Given a text-mode line shorter than 309 characters, When the parser encounters it, Then it SHALL log a warning and skip the line.
- **AC-014:** Given a text-mode line longer than 309 characters, When the parser encounters it, Then it SHALL throw an `InvalidDataException` containing the actual and expected lengths.
- **AC-015:** Given a batch of 1 000 parsed rows, When the batch is flushed, Then all 1 000 rows SHALL be inserted into `Delstat` AND `ImportJob.RowsWritten` SHALL be incremented by 1 000 within the same SQL transaction.
- **AC-016:** Given a completed import (all records processed), When the function reaches the finalization step, Then it SHALL execute `EXEC Postalweb` followed by `EXEC Postalwebboth`, then mark the job `Succeeded` with `CompletedUtc` set to the current UTC timestamp.
- **AC-017:** Given an unhandled exception during processing with `dequeueCount < POSTAL_MAX_RETRIES`, When the catch block executes, Then it SHALL set status to `"QueuedForRetry {dequeueCount}"` and rethrow (triggering Azure Functions retry).
- **AC-018:** Given an unhandled exception during processing with `dequeueCount >= POSTAL_MAX_RETRIES`, When the catch block executes, Then it SHALL mark the job `Failed` with the error message and `CompletedUtc` set, and return without rethrowing.
- **AC-019:** Given a long-running import (> 120 s), When the visibility renewal loop is active, Then `UpdateMessage` SHALL be called every 120 s with the configured visibility timeout, and the loop SHALL stop when processing completes.
- **AC-020:** Given a 10 GB WRK file, When the function processes it, Then it SHALL complete without exceeding the B1 plan's memory limit (3.5 GB) by streaming the blob in chunks rather than loading the entire file into memory.
- **AC-021:** Progress statuses match exact strings listed in §3.1.
- **AC-022:** Invalid integer field throws with field name and raw value.
- **AC-023:** Whitespace-only records skipped; binary trailing partial warned and ignored.
- **AC-024:** Startup log is Information (not Error).
- **AC-025:** Blob log lines contain container + name only (no storage account URL).
- **AC-026:** Bulk insert and RowsWritten update commit or roll back together.
- **AC-027:** Visibility renewal updates and uses new popReceipt; stops cleanly on abort.

## 7. Implementation Notes

- Node Azure Functions v4 programming model (`app.storageQueue` or equivalent).
- `AbortController` for cancellation (renewal loop + SQL/blob operations).
- `mssql` bulk: define columns matching Delstat (string/int), call `.execute()` inside transaction.
- SQL MI: obtain token, set `config.authentication` or connection access token equivalent.
- Tests: unit for parser (valid/invalid/short/long/C/D/whitespace), bulk+checkpoint atomicity (mock or test DB), job claim, visibility loop (mock queue).
- Deployable to existing B1 plan (`NODE|20`).
