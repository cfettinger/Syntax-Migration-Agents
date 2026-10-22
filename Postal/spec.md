# Spec: Legacy desktop import (Form1.vb) → Azure App Service + Blob + Azure SQL

Version 1.4, 2026-10-21 (v1.4: optimized .NET 10 upgrade instructions — full solution scope incl. test project, per-segment done criteria, CI/IaC runtime pins, hosting clarification, rollback plan; v1.3: added .NET 10 upgrade policy and segmented handoff tasks due .NET 8 LTS EOL on 2026-11-10)

> **Source-app note:** `trunk/Form1.vb` is a **VB.NET WinForms** app (.NET Framework, `System.Data.SqlClient`) — **not VB6/COM**. No COM DLLs or OLE DB. Moving parts: fixed-width parser, `TRUNCATE` + row inserts into `Delstat`, then `EXEC Postalweb` and `EXEC Postalwebboth`. "VB6" in older notes means this desktop app.

> **Planning & tracking:** The Postal implementation plan and progress are maintained in [`status.md`](status.md) alongside this spec. Use it to plan the work and track progress as tasks complete.

Read this file and the desktop project. Produce a .NET web app that preserves file-to-database behavior. Target .NET 10 before .NET 8 LTS EOL (2026-11-10). Do not keep the desktop client.

## Runtime Upgrade Policy (.NET 10)

**Deadline:** .NET 8 LTS reaches end of support on **2026-11-10**. All projects must build and run on `net10.0` instead.

**Scope — every project in `Postal.sln`:**

| Project | Target | Notes |
|---------|--------|-------|
| `src/Postal.Api/Postal.Api.csproj` | `net10.0` | ASP.NET Core web app (upload page + import API) |
| `src/Postal.Function/Postal.Function.csproj` | `net10.0` | Isolated worker Function (queue-trigger ImportWorker) |
| `tests/Postal.Api.Tests/Postal.Api.Tests.csproj` | `net10.0` | xUnit test project |

**No functional changes expected.** Parser, API, and worker logic are runtime-agnostic; this is a TFM + package + hosting compatibility upgrade only.

### Segmented upgrade tasks (handoff-ready)

Execute segments **in order**. Each segment is independently committable and has a done criterion — do not start the next segment until the current one's check passes.

**Segment 1 — SDK**
- Install the .NET 10 SDK on the dev machine and the CI runner.
- If `global.json` exists, set it to SDK `10.0.x`.
- **Done when:** `dotnet --list-sdks` shows `10.0.x` and `dotnet build Postal.sln` still succeeds (the 10.x SDK builds `net8.0` targets fine).
***COMPLETE***

**Segment 2 — Retarget all three projects**
- Set `<TargetFramework>net10.0</TargetFramework>` in each csproj in the scope table.
- **Done when:** `dotnet build Postal.sln` succeeds with 0 errors.

**Segment 3 — Postal.Function isolated worker SDK switch**
- Switch the project SDK to `Azure.Functions.Sdk/1.0.0`:

```xml
<Project Sdk="Azure.Functions.Sdk/1.0.0">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.52.0" />
    <!-- keep existing Worker.Extensions.* packages; update versions in Segment 4 -->
  </ItemGroup>
</Project>
```

- Remove the `Microsoft.Azure.Functions.Worker.Sdk` PackageReference (replaced by the project SDK).
- Remove the `OutputType` and `AzureFunctionsVersion` properties (managed by the new SDK).
- Minimum worker version for .NET 10: **2.50.0+** (use `2.52.0`).
- **Done when:** `dotnet build` succeeds and the local host (`func start`) discovers the queue trigger.

**Segment 4 — Package sweep**
- In each project run `dotnet list package --outdated` and update to net10-compatible versions:
  - `Azure.Storage.Blobs`, `Azure.Storage.Queues`
  - `Azure.Identity`
  - `Microsoft.Data.SqlClient`
  - Application Insights telemetry packages
  - `Microsoft.Azure.Functions.Worker.Extensions.*` (queue binding)
- Run `dotnet restore` and resolve any package/runtime breaks.
- **Done when:** `dotnet build Postal.sln` 0 errors and `dotnet test .\tests\Postal.Api.Tests\Postal.Api.Tests.csproj -c Debug` all pass.

**Segment 5 — CI + IaC runtime pins**
- `.github/workflows/deploy-api-function.yml`: point `dotnet/setup-dotnet` at `10.0.x` (or at `global.json`).
- `infra/bicep/main.bicep`: update runtime stacks — Function App `linuxFxVersion: 'DOTNET-ISOLATED|10.0'`, Web App `linuxFxVersion: 'DOTNET|10.0'`.
- Hosting check: .NET 10 is **not supported** on Linux Consumption for Functions. The current shared **B1 dedicated App Service plan** is a supported option — **no plan change needed**. If the plan were ever switched to Consumption, use Flex Consumption (FC1) or Premium instead.
- **Done when:** `az bicep build infra/bicep/main.bicep` exits 0 and the workflow YAML is valid.

**Segment 6 — Validate + deploy**
1. `dotnet build Postal.sln` — 0 errors.
2. `dotnet test .\tests\Postal.Api.Tests\Postal.Api.Tests.csproj -c Debug` — all pass.
3. Local smoke: `func start` + API create/complete/sas-refresh paths.
4. Deploy to Azure (P0 procedure in `status.md`); confirm runtime stacks: `az functionapp show -g Syntax -n postal-worker --query config.linuxFxVersion` and `az webapp show -g Syntax -n postal-api --query config.linuxFxVersion` both report `10.0`.
5. E2E import smoke: generate `sample.wrk` via `testdata/generate_sample.ps1`, run the full import, confirm `ImportJob.Status = Succeeded` and `RowsWritten > 0`.
- **Done when:** all five checks pass against the deployed apps.

### Detailed command checklist (safe placeholders only)

```powershell
# 1) Validate local prerequisites
 dotnet --list-sdks
 dotnet --version
 dotnet build Postal.sln -c Debug
 dotnet test .\tests\Postal.Api.Tests\Postal.Api.Tests.csproj -c Debug --logger "console;verbosity=minimal"

# 2) Validate Azure subscription context (no secrets in output)
az account show --query "{subscription:id, name:name, tenantId:tenantId}" -o table
az account set --subscription "<subscription-name-or-id>"

# 3) Check the existing App Service plan and runtime stack
az appservice plan show --name "<app-service-plan-name>" --resource-group "<resource-group>" --query "{name:name, sku:sku.name, kind:kind, numberOfSites:numberOfSites}" -o json
az webapp show --resource-group "<resource-group>" --name "<api-app-name>" --query "{name:name, defaultHostName:defaultHostName, linuxFxVersion:config.linuxFxVersion}" -o json
az functionapp show --resource-group "<resource-group>" --name "<function-app-name>" --query "{name:name, defaultHostName:defaultHostName, linuxFxVersion:config.linuxFxVersion}" -o json

# 4) Deploy the API and verify the health endpoint
az webapp deploy --resource-group "<resource-group>" --name "<api-app-name>" --src-path "<zip-or-folder>" --type zip
Invoke-WebRequest -Uri "https://<api-hostname>/" -Method Get -UseBasicParsing

# 5) Deploy the Function app (zip deploy is the documented fallback for the .NET 10 worker issue)
az functionapp deployment source config-zip --resource-group "<resource-group>" --name "<function-app-name>" --src "<deploy-zip-path>"
Invoke-WebRequest -Uri "https://<function-hostname>/" -Method Get -UseBasicParsing

# 6) Smoke-test the import path without exposing secrets
$apiBaseUrl = "https://<api-hostname>"
$job = Invoke-RestMethod -Uri "$apiBaseUrl/api/imports" -Method Post -ContentType "application/json" -Body (@{ originalFileName = "sample.wrk"; sizeBytes = 309 } | ConvertTo-Json)
$uploadUrl = $job.sasUri
Invoke-WebRequest -Uri $uploadUrl -Method Put -InFile ".\testdata\sample.wrk" -ContentType "application/octet-stream" | Out-Null
Invoke-RestMethod -Uri "$apiBaseUrl/api/imports/$($job.jobId)/complete" -Method Post -ContentType "application/json"
```

Use placeholders such as `<resource-group>`, `<api-app-name>`, and `<function-app-name>` in shared runbooks. Do not paste connection strings, SAS tokens, or passwords into files or issue comments.

### Rollback

Revert the upgrade commit(s) (TFM + packages + CI/IaC pins) and redeploy with the .NET 8 SDK. All Azure resources (B1 plan, storage, SQL, identity) are runtime-agnostic — no infrastructure rollback is required.

### Acceptance criteria (upgrade complete)

- `dotnet build Postal.sln` succeeds with all three projects on `net10.0`.
- API create/complete/sas-refresh paths function correctly.
- Function queue worker completes an import with `ImportJob.Status = Succeeded` and `RowsWritten > 0`.
- Deployed runtime stacks report `10.0` for both the Web App and the Function App.

## Goal

Replace the desktop app that reads a large local file and writes rows to a database.

1. User opens a website on Azure App Service.
2. Browser uploads the file directly to Azure Blob Storage (block upload, user-delegation SAS). The file never passes through App Service.
3. After the upload commits, a single worker streams the blob, parses it with the same field rules as the desktop app, and inserts into Azure SQL.
4. User sees queued / running / succeeded / failed, plus `RowsWritten`.

## Non-goals

- Do not port the WinForms UI control-for-control.
- Do not register COM DLLs (none exist).
- Do not write the upload to `wwwroot` or `Path.GetTempPath()`.
- Do not load the entire file into memory.
- Do not run the parse inside an HTTP request that receives the file (there is no such request).
- Do not keep a `crlf.exe` pre-step. The parser must accept the raw no-newline file and a CRLF file.

## Azure resources

- App Service: Windows or Linux, .NET 10 preferred (temporary .NET 8 only during transition), Basic B1 or higher. Hosts the site and the API. Enforce HTTPS; application health monitoring on.
- Storage account: private container `imports`. Queue `imports`. Account-level: blob public access **disabled**, HTTPS required, **key access disabled** (Entra/managed identity only — user-delegation SAS and `TokenCredential` work without keys), soft delete on blobs.
- Azure SQL: target database. Firewall allows Azure services. Database user needs `INSERT` on `Delstat` and `ImportJob` plus `EXECUTE` on `Postalweb` and `Postalwebboth` (explicit grants required; `db_datawriter` alone does not include `EXECUTE`). No special bulk privilege needed for ADO.NET `SqlBulkCopy`.
- Identity: App Service system-assigned managed identity, shared by the worker (hosted service or Function in the same repo).
  - **Storage Blob Data Contributor** on the account (read/write blobs).
  - **Storage Blob Delegator** on the account (required to mint user-delegation SAS; Contributor alone is not enough).
  - SQL user mapped from that identity (Entra integrated auth), or a Key Vault secret if identity auth is blocked.
  - Least privilege: no full `db_owner`, no storage `Owner`.
- Do not copy legacy credentials (`syntaxpostal` / `DBCLUSTER` / password in source) into config.
- Observability: Application Insights on the App Service (and the Function if used). Log start, checkpoint, completion, and failure of every import with `jobId` as the correlation ID — track completion, not just start.
  - Worker startup diagnostics must log a **sanitized** SQL configuration summary (server/catalog/auth mode and boolean flags only). Never log raw connection strings, passwords, access tokens, or secret values.

## Runtime flow

1. `GET /` serves the upload page.
2. User selects a file. Browser calls `POST /api/imports` with file name, size, and content type. No file bytes. Reject `sizeBytes` above ~10 GB (client block upload buffers data in memory; the documented national file is ~209 MB, so cap with margin — record the chosen cap in `CONVERSION.md`).
3. API inserts `ImportJob` (`Queued`, new guid, blob name `imports/{jobId}/{originalFileName}`) and returns a user-delegation SAS (Create + Write, ≤ 1 hour) scoped to that blob.
4. Browser uses `@azure/storage-blob` `BlockBlobClient.uploadData` (block size 4–8 MB, concurrency 2–4, retries) against the SAS URL.
5. On commit, browser calls `POST /api/imports/{jobId}/complete`.
6. API checks the blob exists and has size > 0. If status is already `Running` or `Succeeded`, return 409. Otherwise set `Queued` and enqueue `{ jobId }` once.
7. Worker dequeues with a visibility timeout long enough for the longest job. Sets `Running` only if status is `Queued` (compare-and-set). Opens the blob with `BlobClient.OpenRead()` (seekable). Parses, writes batches with transient-fault retry, sets `Succeeded` or `Failed`.
8. Page polls `GET /api/imports/{jobId}`.
9. If a large upload outlives the 1-hour SAS (slow link), the browser gets `StorageRetryError` (403) mid-upload; it calls `POST /api/imports/{jobId}/sas-refresh` (auth'd, job in `Queued`) for a new SAS and re-runs the upload (`uploadData` is idempotent per block key). A plain retry without refresh will never clear. Note: after `/complete` the job remains `Queued` until a worker claims it and transitions it to `Running`, so a SAS refresh is still possible during that window.

## Lease

Do not start the same job on two workers.

- Enqueue a single queue message per job.
- Dequeue with a custom visibility/renewal timeout that exceeds the longest import (a multi-GB import runs many minutes; the default ~60 s visibility re-delivers the message while the job is still healthy). Renew while running, and delete the message only after `Succeeded` / `Failed`.
- Status transition `Queued` → `Running` must be a single conditional update. If zero rows update, another worker owns the job; abandon.
- If the worker runs in the web app, remember the hosted service runs **per instance**: the lease above is what guarantees single execution across scaled-out instances, not the hosting model.

## Data

### ImportJob

- `Id` uniqueidentifier PK
- `BlobName` nvarchar(512) not null
- `OriginalFileName` nvarchar(260) not null
- `SizeBytes` bigint not null
- `Status` nvarchar(20) not null — Queued | Running | Succeeded | Failed
- `Error` nvarchar(max) null
- `CreatedUtc` datetime2 not null
- `CompletedUtc` datetime2 null
- `RowsWritten` int not null default 0 — count of **accepted D records** committed to `Delstat`. Resume key. Not a byte offset.

### Business tables

The app writes one table, `Delstat`, then two stored procedures:

1. `TRUNCATE TABLE Delstat` (fresh start only)
2. Bulk insert of every accepted detail record
3. `EXEC Postalweb` — builds `DelstatWeb`
4. `EXEC Postalwebboth` — builds `DelstatWebBoth`

`Postalweb` / `Postalwebboth` are black boxes. The ASP site reads `DelstatWeb[Both]` plus `DistrictLookup`, `DistrictInfo`, `DistrictLabels`, `Delivery`. Those lookup tables are out of scope. The procedures must run after each successful import.

`Delstat` columns (legacy insert order). Offsets are **0-based** (first byte of the record is index 0). The record-type byte (`D` or `C`) is at index 0; `ZipCode` therefore begins at index 1. Length is the second argument to VB `Substring(start, length)`. C# range `l[start..(start+length)]` must match those lengths. Verify each call against `Form1.vb` before coding; do not trust the `line[1..6]` shorthand.

| # | Column | Type | Start | Length |
|---|--------|------|------:|-------:|
| 1 | `ZipCode` | varchar(5) | 1 | 5 |
| 2 | `RouteID` | varchar(4) | 17 | 4 |
| 3 | `actBCentral` | int | 21 | 5 |
| 4 | `actBCurb` | int | 26 | 5 |
| 5 | `actBndcbu` | int | 31 | 5 |
| 6 | `actBother` | int | 36 | 5 |
| 7 | `actBFacility` | int | 41 | 5 |
| 8 | `actBContract` | int | 46 | 5 |
| 9 | `actBdetached` | int | 51 | 5 |
| 10 | `actBnpu` | int | 56 | 5 |
| 11 | `actRCentral` | int | 81 | 5 |
| 12 | `actRCurb` | int | 86 | 5 |
| 13 | `actRndcbu` | int | 91 | 5 |
| 14 | `actRother` | int | 96 | 5 |
| 15 | `actRFacility` | int | 101 | 5 |
| 16 | `actRContract` | int | 106 | 5 |
| 17 | `actRdetached` | int | 111 | 5 |
| 18 | `actRnpu` | int | 116 | 5 |

Remaining fields in the 309-byte layout (`layout/delstat.doc`) stay ignored.

**Record in `CONVERSION.md`:**

- No foreign keys or lookups in code. Legacy inserts were autocommit, so a crash left `Delstat` partial. Batch commit is an intentional improvement.
- Legacy `CInt` throws on non-numeric. Trim ASCII spaces before `int.Parse`. If the sample file has no spaces, say so.
- `TRUNCATE` blanks the ASP front end for the whole import (same as legacy). Staging-table swap is out of scope unless requested.

## Parse rules

`trunk/Form1.vb` is the source of truth. See Appendix A.

- File read: `File.OpenText` + `ReadLine` until `Peek() == -1` on the CRLF file.
- Field split: fixed-width, 309-character records, 16 fields above. No delimiters.
- Encoding: 7-bit ASCII. `Encoding.ASCII`, BOM detection off.
- Header: first byte `C` is a copyright/volume record. Legacy skipped only the first physical line. **Deviation:** skip every record whose first byte is `C`.
- No date or decimal fields.
- **Both inputs:** raw `delstat.txt` has no CR/LF (one ASCII stream). `delstat.wrk` has CRLF every 309 bytes. Sniff the first chunk from `BlobClient.OpenRead()` for `\r` or `\n`, rewind, then either read lines or slice 309-byte records. Do not use a non-seekable download stream unless you buffer the sniff yourself.
- Bad record: legacy aborted mid-file. New: throw → job `Failed` with `Malformed detail record at …`. Never fail on `C` records.
- Empty lines from CR/LF are skipped.

## Resume

`RowsWritten` counts accepted `D` records whose batch has committed.

- `RowsWritten == 0`: `TRUNCATE TABLE Delstat`, then parse from the start.
- `RowsWritten > 0` and status was `Running`: do **not** truncate. Skip that many accepted `D` records in the parser (both raw and line mode). Do not seek to `RowsWritten * 309` — copyright records and CRLF make a byte seek wrong.
- Checkpoint update and the bulk insert must commit in the **same** SQL transaction. Updating `ImportJob` after the data transaction commits can duplicate a batch on crash.
- `Postalweb` and `Postalwebboth` run only after the final batch, in that last transaction, then status `Succeeded`.

## Transient faults

- Worker: wrap each batch's open→bulk-copy→commit in retry with exponential backoff + jitter on transient SQL errors (40–42 server numbers, connection resets). The checkpoint transaction is the unit of retry: a failed batch rolls back both rows and `RowsWritten`, so retrying is safe.
- Blob reads: retry transient 5xx/connection errors (SDK retry policies cover this; configure them explicitly).
- No circuit breaker needed for a single-job pipeline; do not retry permanent errors (auth, not-found, malformed data).

## API

- `POST /api/imports` — `{ fileName, sizeBytes, contentType }` → `{ jobId, uploadUrl, blobName, uploadNote }`
- `POST /api/imports/{jobId}/complete` — blob must exist and size > 0; 409 if `Running` or `Succeeded`; else enqueue once and return 202
- `POST /api/imports/{jobId}/sas-refresh` — job must be `Queued` (re-upload in progress); returns a fresh ≤ 1-hour SAS for the same blob. Never mints SAS for `Running`/`Succeeded`.
- `GET /api/imports/{jobId}` — job row
- Auth: legacy had none. Add ASP.NET Core cookie auth with one admin user in configuration (password from App Service settings / Key Vault, not source). Do not leave the SAS endpoint anonymous in production.

SAS: user-delegation via managed identity, Create + Write only, expiry ≤ 1 hour, one blob. (User-delegation keys are valid up to 7 days; 1 hour is a policy choice, not a limit.)
Container source: `POSTAL_IMPORTS_CONTAINER` (default `imports`); the blob name is built as `<container>/<jobId>/<file>`, and the SAS URL must target that exact container.
For direct `PUT` uploads to the SAS URL, the client must send `x-ms-blob-type: BlockBlob`.
The API should include an `uploadNote` on the SAS response and on `sas-refresh` responses so any caller knows to send the header before the `PUT`.

## Project layout

```
infra/                  # Bicep (or azd bicep project): storage, queue, app service, SQL, MI, roles
src/ImportWeb/          # ASP.NET Core 10 + one upload page
src/ImportWeb/wwwroot/  # page, @azure/storage-blob
src/Import.Core/        # DelstatParser, job model
src/Import.Worker/      # queue consumer or Functions
```

Deploy with azd/Bicep: validate with `azd provision --preview` (or `az deployment ... what-if`) before applying. Never inline credentials in IaC.

## Deployment slots

**The B1 (Basic) tier itself supports deployment slots, but this subscription is a Free Credits–based account, which does not grant deployment slots on B1.** Deploy directly to the production app.

- No staging slot available for swap testing or zero-downtime blue-green.
- Every `azd deploy` or `az webapp deploy` updates the live app immediately.
- Blue-green deployments (zero-downtime swaps) require a second App Service plan + app; use only if downtime risk is unacceptable.
- If the account is later upgraded to a paid (non-Free-Credits) subscription, B1 slots become available and a staging slot can be added for swap-based deploys.

**Common deployment methods:**

1. **Azure CLI / azd**  
   ```bash
   azd deploy
   ```  
   or  
   ```bash
   az webapp deploy --resource-group Syntax --name postal-api --src-path <zip-or-folder>
   ```

2. **Git / GitHub Actions / Azure DevOps**  
   Configure continuous deployment to the production app.

3. **Zip deploy / VS Code / Visual Studio**  
   Publish straight to the app; no slot to swap.

4. **Kudu / FTP / Web Deploy**  
   Upload files directly to the running site.

Every deploy updates the live app. Plan deployments off-peak, communicate outages, and expect brief downtime.

Plan and track progress of the Postal project in `status.md` (this directory) — update it as tasks complete.

App Service settings, not source:

- `AzureStorage:AccountUrl`
- `AzureStorage:Container` = `imports`
- `ConnectionStrings:Sql` (connection string with `Authentication=Active Directory Managed Identity` or `Password=...` from Key Vault)
- `Queue:Name` = `imports`
- `Admin:User` / `Admin:Password` (cookie auth)

## Acceptance

- A multi-GB file uploads with no App Service request carrying the body.
- A failed block retries; the job stays `Queued` until complete is called.
- An upload that outlives its SAS recovers via `sas-refresh` + re-upload, and completes.
- A second complete on a `Running` or `Succeeded` job returns 409 and does not enqueue again.
- Raw `delstat.txt` and CRLF `.wrk` produce the same rows. Sample file matches legacy counts and key columns (~122,514 records for the ~40 MB sample).
- Restart skips committed `D` records and does not duplicate them.
- Two workers cannot both pass `Queued` → `Running`.
- A transient SQL failure mid-import resumes at the last checkpoint without re-inserting committed batches.
- No file is written under the site content path.
- Progress: expected rows ≈ `SizeBytes / 309` (raw) or `SizeBytes / 311` (CRLF). Page shows `RowsWritten / expected`.

---

## Appendix A — Source facts

1. VB.NET WinForms, .NET Framework, `System.Data.SqlClient`. No COM. `crlf.exe` (David Tribble, Java) was run by hand before the app.
2. `delstat.txt` (raw FTP): no CR/LF. `delstat.wrk`: CRLF every 309 bytes. Sample ~122,514 records, ~40 MB.
3. Layout (`layout/delstat.doc`): 309-byte records. `C` = copyright/volume, `D` = detail. App uses 16 of ~50 fields.
4. `Button1_Click` order: `TRUNCATE TABLE Delstat`; read lines; skip line 1; one concatenated `INSERT` per line; `EXEC Postalweb`; `EXEC Postalwebboth`. No try/catch.
5. Progress bar hard-coded to 700,000. Documented national file 675,341 records / ~209 MB uncompressed.
6. Do not repeat: concatenated SQL, per-row round trips, no transaction, hardcoded credentials, treating only the first line as a header.

## Appendix B — Implementation notes

Parser: `Encoding.ASCII`, record length 309. Field extract must use the start/length table above after checking `Form1.vb`. Trim field text before `int.Parse`.

```csharp
public static DelstatRecord ParseLine(string l)
{
    static int I(string s, int start, int len) =>
        int.Parse(s.AsSpan(start, len).Trim());
    return new DelstatRecord
    {
        ZipCode = l.Substring(1, 5),
        RouteId = l.Substring(17, 4),
        ActBCentral = I(l, 21, 5),
        // remaining ints from the start/length table
    };
}
```

Sniff: read a chunk from `OpenRead()`, look for `\r` or `\n`, `Seek(0)`. Line mode skips empty lines and `C` records; detail must be length 309 and start with `D`. Raw mode reads exactly 309 bytes per record; short trailing chunk fails the job.

Worker, per batch:

1. Fill a `DataTable` (column names exactly `ZipCode, RouteID, actBCentral, … actRnpu`) with up to 50,000 accepted `D` records, after skipping `RowsWritten` on resume.
2. Open a `SqlConnection` / `SqlTransaction`.
3. `SqlBulkCopy` into `Delstat` on that connection and transaction. Dispose the bulk copy.
4. `UPDATE ImportJob SET RowsWritten = @n WHERE Id = @id` on the **same** transaction.
5. Commit. Start a new transaction for the next batch. Wrap steps 2–5 in the transient-fault retry (see "Transient faults").

Final batch: bulk copy, `EXEC Postalweb`, `EXEC Postalwebboth`, set `Succeeded` and `CompletedUtc`, commit.

`SqlBulkCopy` requires `SqlConnection`, not `DbConnection`.

Fresh start (`RowsWritten == 0`): `TRUNCATE TABLE Delstat` before the first batch. Truncate is not rolled back; a failure before the first checkpoint restarts from empty.

Do not implement resume as `Seek(RowsWritten * 309)`.

## Appendix C — Azure best-practices review (2026-10-08)

Reviewed against the Azure MCP "Azure Best Practices" toolset (general code-generation, deployment, Azure Functions) and Microsoft Learn docs. Findings and dispositions:

### Confirmed compliant (verified against Learn docs)

| Spec item | Finding / doc basis |
|-----------|--------------------|
| `Storage Blob Delegator` role for user-delegation SAS issuance | Correct — a SAS minted under a `TokenCredential` requires the Delegator role; **Contributor alone fails** at mint time. (Create a user delegation SAS.) |
| User-delegation SAS ≤ 1 h, Create + Write, single blob | Valid — user-delegation keys are valid up to 7 days from start; short expiries are fine. A refresh path was added (step 9) for very slow uploads. |
| Managed identity for blob storage access | Required — key-based auth is explicitly discouraged; with keys disabled on the account, `TokenCredential` + roles is the only path. |
| No file through App Service; no temp files | Matches the "large upload" guidance (block upload ≥ 8 MiB blocks, concurrency 2–4); the worker streams from `OpenRead()` so nothing hits disk. |
| Single-consumer lease (CAS + custom visibility timeout) | Matches "Background jobs" guidance: multiple instances race on shared resources; resolve via singleton **or** pessimistic locking. We use the queue lease (locking) instead of pinning the App Service to 1 instance, so scale-out stays available. |
| `TRUNCATE` outside the batch transaction | Required — `TRUNCATE` is DDL, issues an implicit commit, and cannot run inside a transaction. |

### Gaps found and fixed in this revision

1. **Queue visibility timeout** (Lease step, Runtime flow 7): default 60 s re-delivery would collide with a multi-minute import. Now: visibility/renewal timeout must exceed the longest job; delete message only after terminal status.
2. **SAS lifetime vs slow uploads** (Runtime flow 9, API): a multi-GB upload on a slow link can outlive the 1-hour SAS with no recovery. Added `POST /api/imports/{jobId}/sas-refresh` (only while `Queued`) + browser re-upload.
3. **Transient-fault handling** (new section): best practice requires retry with exponential backoff for transient failures. Added: batch-level retry scope, transient SQL error classes (40–42), blob read retries, and explicit no-retry for permanent errors.
4. **Storage account hardening** (Azure resources): disable blob public access, HTTPS-only, **disable key access**, soft delete — per the "disable key access on storage accounts / manage data-plane RBAC" guidance.
5. **Functions option caveat** (below): Consumption plan hard-caps at 10 min (105 s for HTTP-triggered). A multi-GB import can exceed that. If the worker becomes a Function: use **isolated worker (v4) model**, and either Flex Consumption (FC1 — never classic Y1 dynamic) or a fixed plan with `maxDuration` ≥ 30 min; queue trigger, auth level `function`, enable Application Insights. This is why the hosted service in the web app is the recommended default: no timeout at all.
6. **Deployment as IaC** (Project layout): `infra/` Bicep folder added; deploy via `azd` with `--preview` / `az what-if` validation first; validate post-deploy via `azd` logs. No credentials in templates.
7. **Observability** (Azure resources): Application Insights enabled; log job start/checkpoint/complete/fail with `jobId` correlation — "track completion, not just start" per the background-jobs guidance.
8. **Upload size cap** (Runtime flow 2): JS block upload buffers data; cap `sizeBytes` well above the ~209 MB national file and say where the cap lives in `CONVERSION.md`.
9. **Auth config path** (API): the single admin user's password comes from App Service settings/Key Vault — never source (best practice: "never hardcode credentials").

### Deferred to CONVERSION.md / build time

- Verify in staging that `SqlBulkCopy` works for the mapped Entra user on the target Azure SQL server (no special bulk privilege expected; if the server restricts it, fall back to parameterized 500-row batched `INSERT` with the same checkpoint design).
- Final `maxDuration` / visibility-timeout values once a real import's wall-clock duration is measured.
- Key Vault reference for the admin password and (if used) the SQL fallback credential.
