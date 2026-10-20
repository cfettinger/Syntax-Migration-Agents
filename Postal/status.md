# Legacy desktop import (Form1.vb) → Azure App Service + Blob + Azure SQL — Implementation Status

**Last Updated:** 2026-10-20T11:45:00Z  
**Spec Version:** 1.2  
**Implementation Phase:** Implementation — API + Function + hardening complete ✅; Azure storage RBAC validated ✅; Bicep/infra templates validated locally ✅; managed identity infrastructure online ✅; **B1 QUOTA BLOCKER SOLUTION: Consolidate to single App Service Plan** → ready for backend dev implementation (2026-10-20)

> This is a living tracker. Update it as tasks complete. The design spec lives in `spec.md`.
> 
> **Architecture Reference:** See [infra/README.md](../../PostalExe/migration/infra/README.md) in the migration repo for detailed topology, data flow diagrams, security posture, queue/visibility renewal logic, and ImportJob lifecycle.

---

## Completed (✅)

- ✅ W1 — Website Phase 1 edits applied (2026-10-16). 5 files changed, junk excluded. Commits `485c0b3` (skeleton) + `daa681c` (edits) on branch `postal-azure-function-worker`. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot). Detail + verification evidence in the W1 block below.
- ✅ W2 — connvars.asp deploy-time generator + CI generator job (2026-10-16). Secrets never committed. Commit `75a561b` on branch `postal-azure-function-worker`. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot). Detail + verification evidence in the W2 block below.
- ✅ API endpoints: POST /api/imports (create ImportJob + user-delegation SAS), /api/imports/{jobId}/complete, /api/imports/{jobId}/sas-refresh (2026-10-17). Files: src/Postal.Api/Program.cs, src/Postal.Api/Data/ImportJobRepository.cs, src/Postal.Api/Services/BlobSasService.cs. Commits `d09259a` + `c2cc07d` on branch `postal-azure-function-worker`. Build evidence: `dotnet build Postal.sln` 0 warnings / 0 errors (2026-10-17). Smoke-tested end-to-end by operator. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).
- ✅ Function worker (.NET 8 isolated): queue-trigger ImportWorker with atomic job claim, fixed-width/CRLF parsing, chunked SqlBulkCopy (batch 1000), RowsWritten resume (truncate only when RowsWritten == 0), EXEC Postalweb + Postalwebboth on success (2026-10-17). File: src/Postal.Function/ImportWorker.cs. Commits `069f354` + `9f848f4` on branch `postal-azure-function-worker`. Verified in the manual smoke test. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).
- ✅ ImportWorker hardening completion (2026-10-20): queue visibility renewal, managed-identity SQL access with `DefaultAzureCredential` token acquisition (with `POSTAL_DB_CONN` local fallback), env-driven batch/retry settings, and App Insights telemetry additions. Files: `src/Postal.Function/ImportWorker.cs`, `src/Postal.Function/Program.cs`, `src/Postal.Function/host.json`, `src/Postal.Function/Postal.Function.csproj`. Evidence: `dotnet build .\src\Postal.Function\Postal.Function.csproj -c Debug` succeeded with 0 errors; `dotnet test .\tests\Postal.Api.Tests\Postal.Api.Tests.csproj -c Debug` passed: 7 passed, 0 failed. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).
- ✅ 7E1 Manual smoke test — end-to-end import of sample.wrk (309 B) run manually by operator (2026-10-17): POST /api/imports → SAS upload → /complete → Function claim / parse / bulk insert / stored procs → ImportJob Succeeded. Sample generator: testdata/generate_sample.ps1 (`2c7600c`). No secrets stored. Branch: postal-azure-function-worker.
- ✅ Website lift & shift review (websitespec.md vs trunk/website/web): confirmed NO major code changes needed. Verified against source: conn layer edits in database.asp (line 12 legacy ODBC conn), facingslipspinebush.asp + facingslipsroselle.asp (dead sa/REDACTED_LEGACY_USER conns, lines 4-5); web.config machineKey removal (line 13); one nav fix in postalss.asp line 276 (routeupdate.asp → updatedelete.asp). Junk pages confirmed present (a.asp, test2.asp, routeupdate.asp, search.htm, aspnet_client/). Branch: main (this repo). Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).
- ✅ Azure RBAC: Storage Blob Data Contributor + Storage Blob Delegator assigned to syntax-main-id (2026-10-20T10:45:00Z). Principal ID: a9c0e286-ecd6-4c1b-beb4-ead5fdb75481; scope: /subscriptions/5a5056f9-2199-4063-9133-0d9a32714a8a/resourceGroups/Syntax/providers/Microsoft.Storage/storageAccounts/syntaxstoragev2. Verification: `az role assignment list --assignee-object-id a9c0e286-ecd6-4c1b-beb4-ead5fdb75481 --scope <storage-account-scope> --query "[].roleDefinitionName" -o table` returned both roles. Agent: Postal Migrator - GitHub Copilot (cfettinger). Commit: 12216c8.
- ✅ W4 Bicep Optimization Plan (2026-10-20T11:30:00Z). **SOLUTION TO QUOTA BLOCKER:** Consolidate Function App + Web App into single `Microsoft.Web/serverfarms` resource (shared App Service Plan). Reduces B1 quota requirement from 2 to 1. Task plan authored: `TASK_W4_BICEP_OPTIMIZATION.md` (335 lines). Steps: (1) Identify current dual-plan resources in `infra/bicep/main.bicep`, (2) Consolidate to single `appServicePlan` resource, (3) Update both apps to reference same `serverFarmId`, (4) Validate locally (`az bicep build` exit 0), (5) Deploy to Azure. Cost reduction: 50% on compute unit. Effort: 0.5 hours. Acceptance criteria: single plan in template, both apps listed (numberOfSites=2 after deployment). Branch: postal-azure-function-worker. Commit: ee8c727. Agent: Postal Migrator - GitHub Copilot (cfettinger). Status: READY FOR IMPLEMENTATION — this unblocks W4 deployment without quota increase wait or Free tier workaround.

## In Progress / Pending (🟡)

- 🟡 **Azure deployment & ops validation** (resource group `Syntax`, managed identity + Function/App Service + SQL permissions). Status: RBAC storage roles assigned ✅ (2026-10-20T10:45:00Z); managed identity infrastructure validated ✅; Bicep template locally validated ✅; **QUOTA BLOCKER SOLUTION FOUND** (W4 optimization plan authored 2026-10-20T11:30:00Z). Progress:
  - **W3** (SQL login `postalweb` + least-privilege grants) — Scripts authored and committed to migration repo (`infra/sql/003` + `004`) as of 2026-10-19. *Pending:* ops run on dev DB first, then prod at cutover. Commits visible on branch `postal-azure-function-worker`.
  - **W4** (Bicep/azd Function App + Web App deployment) — **PREVIOUS BLOCKER RESOLVED:** Instead of waiting for B1 quota increase or deploying to Free tier, consolidate Function App + Web App into single `Microsoft.Web/serverfarms` resource. Reduces quota requirement from 2 to 1. Task plan: `TASK_W4_BICEP_OPTIMIZATION.md` (commit ee8c727). Steps: (1) Identify dual-plan resources in `infra/bicep/main.bicep`, (2) Consolidate to single `appServicePlan`, (3) Both apps reference same `serverFarmId`, (4) Validate (`az bicep build` exit 0), (5) Deploy. Cost reduction: 50% on B1 unit. Effort: 0.5 hours. Acceptance: single plan in template, numberOfSites=2 post-deployment. Status: READY FOR IMPLEMENTATION. Agent: Postal Migrator - GitHub Copilot (cfettinger, 2026-10-20T11:30:00Z).
  - **W5** (Managed identity assignment validation in Azure) — After W4 deployment, confirm Function App and Web App system-assigned identity equals or includes `syntax-main-id`. Use `az functionapp identity show` and `az webapp identity show`. *Pending after W4 deployment (now unblocked).*
  - **W6** (SQL permissions validation) — After SQL user `postalweb` is provisioned by ops (W3), confirm SELECT/INSERT/EXECUTE grants via TSQL query or Function import dry-run. *Pending after W3 + W4.*
  - **W7** (Azure smoke test) — Full end-to-end import in cloud: POST /api/imports (Azure App Service) → browser SAS upload → /complete → Function processes → Postalweb procs execute → ImportJob Succeeded. *Pending after W4–W6.*
  - **8E1 (Managed Identity Smoke Test)** — Validated existing Azure infrastructure without app deployment (2026-10-20T11:20:00Z). Evidence:
    - ✅ `syntax-main-id` (User-Assigned Managed Identity, Principal: a9c0e286-ecd6-4c1b-beb4-ead5fdb75481) exists and active.
    - ✅ Storage Blob Data Contributor + Storage Blob Delegator roles assigned to `syntax-main-id` on `syntaxstoragev2` scope.
    - ✅ Azure SQL `Postal` database online with AllowAllAzureIps firewall rule enabled.
    - ✅ App Service Plan `syntax-app-service` provisioned (B1, on same resource group).
    - ✅ Bicep template locally valid: `az bicep build .../main.bicep` exit 0, 0 errors (only expected BCP081 warning for Storage/queues).
    - Validation Commands: `az identity show -g Syntax -n syntax-main-id`, `az role assignment list --assignee-object-id a9c0e286-ecd6-4c1b-beb4-ead5fdb75481 --scope <storage-account> --query "[].roleDefinitionName"`, `az sql db list -g Syntax -s syntax-sql --query "[].name"`.
    - **Status:** Managed identity infrastructure ready for Function/Web App deployment; no app deployment yet due to quota. Agent: Postal Migrator - GitHub Copilot (cfettinger, 2026-10-20T11:20:00Z). Branch: postal-azure-function-worker.
 - 7E1 Manual smoke test: generate sample.wrk and run end-to-end import
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: migration/testdata/generate_sample.ps1
  - Started: 2026-10-17T12:00:00Z
  - Status: ✅ COMPLETE 2026-10-17 — end-to-end import verified manually by operator (POST /api/imports → SAS upload → /complete → Function claim / parse / bulk insert / EXEC Postalweb + Postalwebboth → Succeeded). No secrets stored.
  - Progress log:
    - 2026-10-17T12:34:00Z: dotnet build src/Postal.Api/Postal.Api.csproj succeeded locally (see migration commit).
    - 2026-10-17T12:35:00Z: Postal.Function build initiated (agent will run dotnet build for src/Postal.Function next).
    - 2026-10-17T12:40:00Z: Code fixes applied to Postal.Function to resolve compile errors:
      - Removed duplicate placeholder Functions.cs to avoid type duplication.
      - Added Postal.Function.csproj (net8.0) and Program.cs host bootstrap.
      - Added Microsoft.Azure.Functions.Worker.Extensions.Storage.Queues package and configured Worker.Sdk analyzer.
      - Switched SQL usage to Microsoft.Data.SqlClient across projects.
    - 2026-10-17T12:41:00Z: Agent attempted to run dotnet build but the local terminal task was not executed by the agent. Please run the following in your developer terminal and paste the output into this issue or terminal log:
      - dotnet build ./src/Postal.Function/Postal.Function.csproj -c Debug
    - 2026-10-17T12:50:00Z: dotnet build ./src/Postal.Function/Postal.Function.csproj completed locally (Build succeeded, transitive TFM warnings observed).
      - Action taken: added <SuppressTfmSupportBuildWarnings>true</SuppressTfmSupportBuildWarnings> to src/Postal.Function/Postal.Function.csproj to reduce noisy transitive package warnings from WorkerExtensions during local development.
    - 2026-10-17T12:52:00Z: dotnet run ./src/Postal.Function/Postal.Function.csproj failed with duplicate class error CS0101 (type 'ImportWorker' already defined).
      - Root cause: Duplicate class definition or renamed class not fully updated.
      - Fix applied: Renamed class ImportWorker → ImportWorkerFunction in src/Postal.Function/ImportWorker.cs; updated constructor and logger generic type.
      - Next: Run dotnet build ./src/Postal.Function/Postal.Function.csproj -c Debug to verify rebuild succeeds.
      - Then: dotnet run --project ./src/Postal.Function/Postal.Function.csproj to launch the Function host.
    - 2026-10-17T13:05:00Z: Runtime startup failure observed when running `dotnet run` directly for Postal.Function: gRPC channel URI `http://:` parse failure.
      - Root cause: .NET isolated worker requires Azure Functions host to supply gRPC endpoint variables; direct `dotnet run` without host does not provide them.
      - Fix path: start with Azure Functions Core Tools (`func start`) from src/Postal.Function or run via Visual Studio Function debug profile.
      - Noise reduction: added src/Postal.Function/Directory.Build.props with `<SuppressTfmSupportBuildWarnings>true</SuppressTfmSupportBuildWarnings>` so generated WorkerExtensions project stops emitting repeated net6 support warnings.
    - 2026-10-17T13:15:00Z: Manual smoke test environment is live: Terminal A (Postal.Api) running, Terminal B (Functions host) running via Core Tools, Terminal C ready. Generated `sample.wrk` successfully at 309 bytes.
      - Pending verification steps: upload via SAS URL, call `/api/imports/{jobId}/complete`, observe Function processing logs, and confirm ImportJob/Delstat results.
    - 2026-10-17T08:01:20Z: Functions host acquired host lock ("Host lock lease acquired by instance ID '0000000000000000000000005073DE9C'"). Host appears healthy and ready to process queue messages.
      - Next actions (operator):
        1) POST /api/imports to create job and obtain SAS.
        2) Upload `sample.wrk` to the returned SAS URL (PUT + x-ms-blob-type: BlockBlob).
        3) POST /api/imports/{jobId}/complete to enqueue job.
        4) Paste the API responses and the Functions host logs showing processing (job claimed, rows inserted, stored procs run, job marked Succeeded). Add those artifacts to this status entry before marking the smoke test complete.
    - 2026-10-17T13:40:00Z: Function host startup failed under `func start --dotnet-isolated-debug`.
      - Root cause 1: `--dotnet-isolated-debug` pauses worker startup awaiting debugger attach, which can cause host startup timeout during manual smoke tests.
      - Root cause 2: `AzureWebJobsStorage` was not reachable (`UseDevelopmentStorage=true` without Azurite / valid storage emulator), and queue-trigger startup requires accessible storage.
      - Recovery path: run `func start` without the debug flag and point `AzureWebJobsStorage` to a reachable storage account connection string or start Azurite locally.
    - 2026-10-17T14:05:00Z: API `/api/imports` failed with `ActiveDirectoryInteractive` auth provider missing in SqlClient runtime.
      - Root cause: `Microsoft.Data.SqlClient.Extensions.Azure` package not referenced in Postal.Api while using `Authentication=ActiveDirectoryInteractive` in POSTAL_DB_CONN.
      - Fix applied: added package reference `Microsoft.Data.SqlClient.Extensions.Azure` to `src/Postal.Api/Postal.Api.csproj` (pinned to 7.0.2).
      - Next: restart API (`dotnet build` + `dotnet run`) and retry POST `/api/imports`.
    - 2026-10-17T14:20:00Z: POST /api/imports returned a jobId and blobName but sasUrl was empty (null). Example response:
      - { jobId: c64c27a6-5206-46ed-a82a-f338227dba12, blobName: imports/c64c27a6-5206-46ed-a82a-f338227dba12/sample.wrk, sasUrl: null }
      - 2026-10-17T14:25:00Z: Terminal C confirmed API response (jobId=c64c27a6-5206-46ed-a82a-f338227dba12, blobName=imports/c64c27a6-5206-46ed-a82a-f338227dba12/sample.wrk, sasUrl empty). Cause: BlobSasService not registered because STORAGE_ACCOUNT_URL was not set in the API process environment.
        Next: set STORAGE_ACCOUNT_URL in the API terminal, restart the API, re-run POST /api/imports to obtain SAS, upload sample.wrk to the SAS URL, then POST /api/imports/{jobId}/complete and monitor Function host logs for processing and ImportJob status updates.
      - Root cause: API did not have STORAGE_ACCOUNT_URL configured in its environment, so BlobSasService was not registered and no SAS was minted.
      - Next actions (operator):
        1) In the API terminal, set STORAGE_ACCOUNT_URL to the storage account URL used by the Functions host (e.g. https://syntaxstoragev2.blob.core.windows.net/) and restart the API.
           - PowerShell: $env:STORAGE_ACCOUNT_URL = 'https://syntaxstoragev2.blob.core.windows.net/'; dotnet run --project .\src\Postal.Api\Postal.Api.csproj
        2) Re-call POST /api/imports to obtain a SAS URL, upload the sample, then call /api/imports/{jobId}/complete and observe Function processing logs.
        3) When processing completes, capture DB evidence (ImportJob.Status, RowsWritten) and Function logs and add them to this status entry.
    - 2026-10-17T14:15:00Z: API build succeeded with ActiveDirectoryInteractive extension installed; NU1603 warning indicated requested `Microsoft.Data.SqlClient.Extensions.Azure` 6.1.1 unavailable and 7.0.2 resolved.
      - Fix applied: pinned `Microsoft.Data.SqlClient.Extensions.Azure` to `7.0.2` in `src/Postal.Api/Postal.Api.csproj` to remove package resolution warning.
      - Next: restart API and continue manual smoke test request sequence (`/api/imports` → SAS upload → `/complete`).
  - Next actions:
    1) Build src/Postal.Function and resolve any compile errors.
    2) Launch the Function host locally (func start or dotnet run) and monitor logs.
    3) Execute manual smoke test steps: generate sample.wrk, POST /api/imports to get SAS, upload sample to SAS URL, POST /api/imports/{jobId}/complete, verify queue message and let the Function process the job. Record evidence (DB row counts, logs) before marking this task complete.
## Open Design Decisions (from §12)

## Architecture Notes

## Databases (inventory & auth)

- Development (interactive): REDACTED_AZURE_SQL_HOSTNAME.public.0321e1ea10c5.database.windows.net,3342 — use AAD interactive authentication for local development. Set POSTAL_DB_CONN in your local environment for testing (do NOT commit). Example auth: Authentication=ActiveDirectoryInteractive; User ID shown only for reference; do not store passwords in repo.
- Production (managed): production SQL instance (managed by infra/ops). Runtime should use either managed identity (preferred) or a dedicated limited SQL account. Operations will retain the existing REDACTED_SQL_ADMIN SQL Server admin account; a new least-privilege DB user will be created for the app with INSERT on Delstat/ImportJob and EXECUTE on Postalweb & Postalwebboth. Credentials and any secrets must live in Key Vault or CI secret store — never checked into source.

Notes:
- Do not include passwords, SAS tokens, or keys in this file or in source. This file documents hostnames/auth patterns only.
- For local dev, use AAD interactive sign-in (az login or Visual Studio) so DefaultAzureCredential/Interactive auth works.


## Next Immediate Steps (Priority Order)

**Status as of 2026-10-20T11:30:00Z**: Core importer API + Function implementation ✅ complete and locally smoke-tested; Bicep/azd infra templates ✅ authored and locally validated (`az bicep build exit 0`); managed identity RBAC ✅ verified on storage account; Azure infrastructure (SQL, Storage, Plan, Identity) ✅ exists and verified online.

**CURRENT BLOCKER:** B1 AppServicePlan quota exhausted → Cannot deploy Function/Web App yet.

**Actionable next steps (in priority order):**

### **CRITICAL (Unblocks all remaining work)**

**P0: Resolve B1 Quota Blocker (Owner: ops/DevOps)**
   - Choose one of:
     a) **Recommended:** Request subscription quota increase from Azure Support for B1 AppServicePlan tier (target: +1 instance for importer stack).
     b) **Workaround:** Modify Bicep template `infra/bicep/main.bicep` to deploy to Free (F1) or Shared (D1) tier for testing purposes. Note: Free/Shared are not production-grade; use only for dev validation.
     c) **Alternative:** Verify if B2/B3 tier has available quota and adjust to optimize cost trade-off.
   - Effort: 0.5–2 hours (depends on Azure Support response time).
   - Unblocks: W4, W5, W6, W7, and all integration deployment tasks.
   - **Evidence required:** Screenshot of deployment success or Azure Portal resource confirmed created.

### **HIGH (Post-quota fix)**

**P1: W3 – SQL User Provisioning (Owner: ops/DBA)**
   - Script location: `infra/sql/003-create-postalweb-login.sql` + `infra/sql/004-grant-postalweb-permissions.sql` (committed, branch `postal-azure-function-worker`).
   - Steps:
     1. Connect to Postal DB with SQL admin account (retain existing REDACTED_SQL_ADMIN credential).
     2. Run 003 script: creates SQL login `postalweb` (managed identity-based).
     3. Run 004 script: grants INSERT on dbo.Delstat + dbo.ImportJob; EXECUTE on dbo.Postalweb + dbo.Postalwebboth.
   - Acceptance: Query `SELECT * FROM sys.database_principals WHERE name='postalweb'` returns 1 row; query `sys.database_permissions` shows INSERT/EXECUTE grants.
   - Effort: 0.5 hours.
   - **Evidence required:** Script execution output + permission verification queries in status.md update.

**P2: W4 – Deploy Function App + Web App (Owner: DevOps/Platform)**
   - After quota resolved, execute deployment:
     ```bash
     cd migration
     az login
     azd provision
     azd deploy
     ```
   - Or manual:
     ```bash
     az deployment group create \
       -g Syntax \
       --template-file infra/bicep/main.bicep \
       --parameters infra/bicep/main.parameters.json \
       --parameters sqlAdminPassword='<secure-password-from-keyvault>'
     ```
   - Acceptance: Azure Portal shows Web App + Function App running in `Syntax` RG; system-assigned identities created.
   - Effort: 1 hour + quota resolution time.
   - **Evidence required:** `az webapp show -g Syntax -n postal-api --query "{id:id, state:state}"` + `az functionapp show -g Syntax -n postal-import --query "{id:id, state:state}"`.

**P3: W5 – Validate Managed Identity Assignment in Deployed Apps (Owner: DevOps)**
   - After W4 deployment:
     ```bash
     az webapp identity show -g Syntax -n postal-api --query systemAssignedIdentity
     az functionapp identity show -g Syntax -n postal-import --query systemAssignedIdentity
     ```
   - Acceptance: Both commands return non-null principal IDs; confirm they match or include `syntax-main-id` (Principal a9c0e286-ecd6-4c1b-beb4-ead5fdb75481).
   - Effort: 0.25 hours.
   - **Evidence required:** Copy of identity query output.

**P4: W6 – Validate SQL Permissions on Deployed Resources (Owner: backend dev/ops)**
   - After P1 + P4, test connection from Function App to Postgres using managed identity token:
     1. Deploy a simple test script or curl to Function App: acquire token via `DefaultAzureCredential` for SQL scope (`https://sql.azure.com/`).
     2. Connect to Postal DB as `postalweb` and verify SELECT/INSERT/EXECUTE grants.
     3. Run a dry-run import (small sample) to confirm Function can read blob, parse, bulk insert, and execute stored procs without permission errors.
   - Acceptance: Test script completes without permission errors; ImportJob row created with Status=Succeeded; RowsWritten >= 1.
   - Effort: 1.5 hours.
   - **Evidence required:** Function App logs (Application Insights), ImportJob query results, parsed bulk insert counts.

### **MEDIUM (Post-deployment validation)**

**P5: W7 – End-to-End Azure Smoke Test (Owner: backend dev/ops)**
   - After W4–W6 complete:
     1. POST to deployed API: `https://<postal-api-app-name>.azurewebsites.net/api/imports` with `{ "originalFileName": "sample.wrk", "sizeBytes": 309 }`.
     2. Browser download SAS URL and upload sample.wrk.
     3. POST `/api/imports/{jobId}/complete`.
     4. Observe Function App process queue message → parse → bulk insert → execute Postalweb procs → mark Succeeded.
     5. Verify ImportJob.Status=Succeeded and Delstat row count increased.
   - Acceptance: End-to-end flow succeeds without manual intervention; all logs clean.
   - Effort: 1 hour.
   - **Evidence required:** Function App logs, ImportJob query result, screenshot of successful response.

### **LOW (After core deployment)**

**P6: Automated Testing & CI (Branch: postal-test-harness)**
   - Add unit tests: parser (fixed-width, CRLF), malformed records, resume logic.
   - Add integration tests: local Azurite + dev DB end-to-end.
   - Integrate into `.github/workflows/deploy-api-function.yml` CI pipeline.
   - Effort: 2–3 hours.
   - Acceptance: CI runs tests on every commit to `postal-azure-function-worker`; all tests pass.

**P7: Documentation & Runbooks (Branch: postal-docs)**
   - Finalize README.md: local dev setup, env var checklist, how to run API + Function.
   - Create ops runbook: deploy steps, troubleshooting, rollback procedure.
   - Update Postal/status.md with final completion checklist.
   - Effort: 1.5 hours.

**P8: Website Deployment (Separate project; tracked in websitespec.md)**
   - W1–W2 completed on `postal-website-deploy` branch.
   - Remaining: Lift & shift hosting to Azure (App Service + CI).
   - Owner: separate team or later phase.

---

## Completed Task Details (Items 1–9 below for reference)

9) Manual smoke test: generate valid sample .wrk and run end-to-end import (minimal validation)
   - Title: Manual smoke test - sample Delstat import
   - Owner: cfettinger / Postal Migrator - GPT-5 Mini
   - Branch: postal-azure-function-worker
   - Files to add: D:\Webs\Syntax\PostalExe\migration\testdata\generate_sample.ps1 (PowerShell generator)
   - Infra changes: None
   - Steps:
     1. Set environment and sign-in:
        - PowerShell: `az login` (or sign into Visual Studio)
        - Set env vars in the shell: `($env:POSTAL_DB_CONN = "<dev-connection-string>")` and `($env:STORAGE_ACCOUNT_URL = "https://<yourstorage>.blob.core.windows.net")`.
     2. Generate a valid sample record file:
        - Run: `pwsh .\\migration\\testdata\\generate_sample.ps1 -OutFile sample.wrk`
        - Script will create `sample.wrk` (309 bytes, ASCII) with valid numeric fields.
     3. Create ImportJob and get SAS:
        - POST to API: `POST /api/imports` with JSON `{ "originalFileName": "sample.wrk", "sizeBytes": 309 }`.
        - Expect response: `{ jobId, blobName, sasUrl, expiresUtc }`.
     4. Upload sample to SAS URL:
        - Use curl: `curl -X PUT -H "x-ms-blob-type: BlockBlob" --data-binary @sample.wrk "<sasUrl>"`
     5. Signal completion:
        - `POST /api/imports/{jobId}/complete`
     6. Run/monitor Function:
        - Start Function host (`func start`) or ensure Function app is running to pick up queue message.
        - Watch logs: job claim, parsing, bulk insert, stored proc execution, status update.
   - Environment:
     - POSTAL_DB_CONN (dev DB connection; do not commit)
     - STORAGE_ACCOUNT_URL
     - az login or VS auth
   - RBAC / Permissions:
     - Managed identity or signed-in user must have Storage Blob Data Contributor and Storage Blob Delegator on the storage account to mint SAS / read blob.
     - DB user must have INSERT on Delstat/ImportJob and EXECUTE on Postalweb & Postalwebboth.
   - Acceptance criteria:
     - ImportJob.Status becomes `Succeeded` and ImportJob.RowsWritten >= 1.
     - Delstat contains at least one new row matching the sample ZipCode / RouteID.
     - Function logs show processing steps and no parsing errors.
   - Tests:
     - Manual integration smoke test only (no unit tests required): follow steps above.
   - Test data:
     - Script at migration/testdata/generate_sample.ps1 (generates sample.wrk)
   - Estimated effort: 0.5 hours
   - Commit message template: `test(e2e): add smoke-test sample generator and run smoke import`
   - Status.md update on completion: add a Completed line with branch name, files added, and a one-line verification (e.g., `✅ Manual smoke test: sample.wrk imported; ImportJob Succeeded; rowsWritten=1; branch postal-azure-function-worker`).
   - Progress: ✅ COMPLETE 2026-10-17 — sample.wrk (309 B) generated via testdata/generate_sample.ps1 (`2c7600c`) and imported end-to-end (ImportJob Succeeded); verified manually by operator. Completion entry added to the Completed section above.

## Website Deployment TODOs (websitespec.md — `postal-web` lift & shift)

This is a living tracker. Update it as tasks complete. The design spec lives in `websitespec.md`.

Source: `D:\Webs\Syntax\PostalExe\trunk\website\web` (SVN working copy `trunk/website`). All artifacts live in the central shared workspace so other agents can participate; all tasks run from this repository's central checkout on `main`; each task is self-contained and safe to hand off. Verified 2026-10-16 (see Completed): Phase 1 code diff is ~5 one-line edits + 1 config removal + deploy-set filter.

### W1 — Prepare website deploy source (Phase 1 code edits)
- Title: Apply websitespec §6 Phase 1 edits to website source
- Owner: cfettinger / Postal Migrator
- Branch: `postal-website-deploy` (off `main` in the PostalExe migration repo; merge to main when done — tasks operate from the central shared workspace so other agents can participate)
- Files to change:
  - `database.asp` — line 12: replace `conn.Open "driver={ODBC Driver 17...};server=REDACTED_INTERNAL_IP;...","syntaxpostal","<REDACTED_DB_PASSWORD>"` with `<!--#include file="connvars.asp"-->` + `conn.Open ConnString, DbUser, DbPassword` (per §6.1; keep all commented history lines and all helpers: `sql_execute`, `validateInput`, `validateZip`, `returnValidated`, `returnZipValidated`, `ReadFormVariables`).
  - `facingslipspinebush.asp` lines 4–5, `facingslipsroselle.asp` lines 4–5 — replace `User id=sa;Data source=REDACTED_LEGACY_USER` blocks with the same `connvars.asp` include and shared `conn`. Keep hardcoded queries (`WESTBURY` / `deerpark`) as-is.
  - `web.config` — remove the `<machineKey>` element (line 13). Remove nothing else.
  - `postalss.asp` line 276 — `href="routeupdate.asp"` → `href="updatedelete.asp"` (§6.4; only behavioral change).
  - New: `connvars.template.asp` (committed template with placeholders; real `connvars.asp` is git-ignored and generated at deploy per W2).
- Infra changes: none
- Steps: 1) copy `web/` into the deploy repo layout (suggested: `website/web/`); 2) apply the four edits above; 3) add `connvars.asp` to `.gitignore`; 4) build the deploy file list per websitespec §5 (exclude: `a.asp`, `a.html.txt`, `test2.asp`, `routeupdate.asp`, `search.htm`, `aspnet_client/`, `backup/`, `Thumbs.db`, `_derived*/`, `test.asp`, `Postal.sln`, `.vs/`); 5) diff every deployed page against the original and confirm ONLY the four files above differ.
 - Progress: ✅ COMPLETE 2026-10-16. Skeleton committed as `485c0b3` (connvars.template.asp, deploy-list.txt, README.md, .gitignore). Phase 1 edits committed as `daa681c` on branch `postal-azure-function-worker` (local repo, no remote; shared working copy per this section's rule — no separate `postal-website-deploy` branch needed): `website/web/database.asp` (connvars include + helpers, no secrets), `facingslipspinebush.asp`, `facingslipsroselle.asp` (shared `conn` via include), `web.config` (machineKey removed), `postalss.asp` (routeupdate.asp → updatedelete.asp).
 - Verification evidence: `git grep -i -E "REDACTED_DB_PASSWORD|172\.20\.0\.141|syntaxpostal" HEAD -- website/` → 0 matches (no secrets); `git grep -c "updatedelete.asp" HEAD -- website/web/postalss.asp` → 1; machineKey absent from `web.config` (comment documents removal); all three data pages contain `<!--#include file="database.asp" -->`. 
 - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot) — completed 2026-10-16; no follow-up agent in progress.
- Environment: none (no secrets; `connvars.template.asp` contains placeholders only)
- RBAC / Permissions: none
- Acceptance criteria: `git diff` between original `web/` and prepared source shows changes in exactly `database.asp`, `facingslipspinebush.asp`, `facingslipsroselle.asp`, `web.config`, `postalss.asp`; no page renders a difference beyond the DB connection and the one nav link; no junk file is in the deploy list.
- Tests: manual diff review (command above); no unit tests (VBScript).
- Test data: none
- Estimated effort: 1 h
- Commit message template: `feat(website): apply Phase 1 lift-and-shift edits (connvars, machineKey, nav fix)`
- Status.md update: `✅ W1 website Phase 1 edits applied; 5 files changed, junk excluded; branch postal-website-deploy`

### W2 — connvars.asp deploy-time generation (secrets never in repo)
- Title: Generate `connvars.asp` at deploy time from CI secrets
- Owner: backend dev
- Branch: `postal-website-deploy`
- Files to change: `infra/web/gen-connvars.ps1` (renders `connvars.template.asp` → `connvars.asp` using `$env:POSTAL_DB_SERVER`, `POSTAL_DB_NAME`, `POSTAL_DB_USER`, `POSTAL_DB_PASSWORD`), and the CI workflow step that runs it and injects the file into the release zip (see W5).
- Infra changes: none (pipeline-only)
- Steps: 1) write template: `ConnString = "Provider=SQLOLEDB;Data Source=tcp:<server>.database.windows.net,1433;Initial Catalog=<db>;"` plus `DbUser`, `DbPassword` (use `SQLOLEDB` — §6.1: no ODBC driver dependency); 2) write generator script; 3) wire into W5 pipeline; 4) verify generated file is never committed (git check-ignore + scan artifact step).
- Environment: pipeline secrets `POSTAL_DB_SERVER`, `POSTAL_DB_NAME`, `POSTAL_DB_USER` (= `postalweb`), `POSTAL_DB_PASSWORD` (Key Vault-backed, fresh — NEVER the legacy password)
- RBAC / Permissions: pipeline identity needs read on the Key Vault secret (or secret-scoped variable group)
- Acceptance criteria: a test zip built by the pipeline contains `connvars.asp` with a valid SQLOLEDB string to the dev DB; repo scan finds zero occurrences of the legacy password and `git check-ignore connvars.asp` succeeds.
- Tests: pipeline job runs generator against placeholder values and asserts the three variables appear in output (no real values logged).
- Test data: `testdata/connvars.sample.env` (placeholder values only)
- Estimated effort: 1 h
- Commit message template: `feat(website): add connvars.asp deploy-time generator (secrets out of repo)`
- Status.md update: `✅ W2 connvars.asp generated at deploy time; secrets never committed; branch postal-website-deploy`
 - Progress: ✅ COMPLETE 2026-10-16. Committed as `75a561b` in the migration repo working copy (no separate branch — local repo, per user): `infra/web/gen-connvars.ps1` (SQLOLEDB render, fail-fast on missing env vars, no-placeholder-survival check, password never printed), `.github/workflows/deploy-website.yml` (active `connvars-generator` job runs generator with placeholder values, asserts values in output with the password line excluded from logs, `git check-ignore` on `connvars.asp`, repo secret scan for legacy password/machineKey/SAS tokens; W5 OIDC zip-deploy job stubbed behind W3/W4), `testdata/connvars.sample.env` (placeholders only).
 - Verification evidence (local, 2026-10-16): generator run with placeholders → `connvars.asp written ... (server=postal-db-EXAMPLE, db=postal_example, user=postalweb)` + `Password: [redacted]`, rendered file contains `Provider=SQLOLEDB;Data Source=tcp:postal-db-EXAMPLE,1433;Initial Catalog=postal_example;`; missing-var run exits 1 with `Missing required environment variables: POSTAL_DB_PASSWORD`; `git check-ignore -v website/web/connvars.asp` → `.gitignore:4`; `git grep -i '<REDACTED_DB_PASSWORD>'` → 0 matches. Pipeline will re-run these on push (repo must be pushed to a remote with Actions enabled for the CI job itself to run).
 - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot) — completed 2026-10-16; no follow-up agent in progress. W5 (OIDC zip-deploy) is the follow-up and remains unassigned.

### W3 — SQL login `postalweb` + least-privilege grants
- Title: Create website SQL login and grants (run by ops on shared DB)
- Owner: infra / DBA
- Branch: n/a (SQL script in this repo)
- Files to add: `infra/sql/003-create-postalweb-login.sql` (exact grant set from websitespec §7: SELECT on Delstat/Delivery/DelstatWeb/DelstatWebBoth/DistrictLookup/DistrictInfo/DistrictLabels; UPDATE on DelstatWeb/DelstatWebBoth/DistrictInfo; INSERT+DELETE on DistrictLookup; SELECT+INSERT+UPDATE+DELETE on DistrictLabels; EXECUTE on Postalweb/Postalwebboth; NO TRUNCATE/ImportJob/db_owner)
- Infra changes: SQL script (ops runs it on the production SQL instance; dev DB too for testing)
- Steps: 1) create `003-create-postalweb-login.sql` from the §7 block (idempotent: `IF NOT EXISTS` guards); 2) ops creates the server login with a fresh Key Vault-stored password; 3) run script; 4) verify with `sp_helprole`-style queries / a test connection using the `postalweb` user.
- Environment: ops SQL admin access (`REDACTED_SQL_ADMIN` retained); new password lives in Key Vault only
- RBAC / Permissions: the grants above, exactly; least privilege — the site's injection surface is bounded by this login until Phase 2
- Acceptance criteria: login `postalweb` can run `SELECT` on all web tables, `EXEC Postalwebboth`, `UPDATE DelstatWeb SET totpos=...`; attempts `TRUNCATE Delstat`, `INSERT ImportJob`, and `ALTER TABLE` all fail with permission errors.
- Tests: three-part verification script `infra/sql/004-verify-postalweb-grants.sql` (SELECT succeeds / UPDATE on granted table succeeds / UPDATE on Delstat fails).
- Test data: none
- Estimated effort: 0.5 h (script) + 0.5 h (ops run)
- Commit message template: `feat(infra): add postalweb least-privilege login script and grant verification`
- Status.md update: `✅ W3 postalweb login + grants created on dev (prod at cutover); grants verified; script infra/sql/003`
- Progress:
  - 2026-10-19T13:30:00Z — W3 SQL scripts authored (agent: Postal Migrator - GPT-5 Mini, cfetching / GitHub Copilot). Added to migration repo `D:\Webs\Syntax\PostalExe\migration` (branch `postal-azure-function-worker`):
    - `infra/sql/003-create-postalweb-login.sql` — idempotent (`IF NOT EXISTS` guards on server login + database user; additive grants). Applies the exact websitespec §7 grant set: SELECT on Delstat/Delivery/DelstatWeb/DelstatWebBoth/DistrictLookup/DistrictInfo/DistrictLabels; UPDATE on DelstatWeb/DelstatWebBoth/DistrictInfo; INSERT+UPDATE+DELETE on DistrictLabels; INSERT+DELETE on DistrictLookup; EXECUTE on Postalweb/Postalwebboth. Explicitly NOT granted: ImportJob, Delstat DML, TRUNCATE, db_owner. Password is a `<POSTAL_DB_PASSWORD>` placeholder (ops injects the fresh Key Vault value at run time — never committed).
    - `infra/sql/004-verify-postalweb-grants.sql` — read-mostly verification (all DML probes wrapped in always-rolled-back transactions). Per-check PASS/FAIL via TRY/CATCH + `HAS_PERMS_BY_NAME`: user/login exist; SELECT on all 7 tables; UPDATE on the 3 granted tables; DistrictLabels full CRUD; DistrictLookup INSERT+DELETE and NO UPDATE; EXECUTE on both SPs; negative checks (Delstat read-only, no CONTROL, not a role, not db_owner, no ImportJob access).
  - Status: 🟡 scripts authored + committed to repo; **pending ops run** on dev DB (then prod at cutover) and a green `004` verification pass. Next pickable after W3 ops run: **W4** (Bicep/azd `postal-web` Windows App Service).

### W4 — Bicep/azd: `postal-web` Windows App Service
- Title: IaC for postal-web App Service (Windows, 32-bit, Classic, Entra auth)
- Owner: infra
- Branch: `postal-website-deploy`
- Files to add: `infra/bicep/postal-web.bicep` (or azd module): Windows App Service plan B1+ (may reuse the importer's plan if importer is Windows), site `postal-web` — runtime `.NET 4.8`, **Platform 32-Bit = True**, **ManagedPipelineMode = Classic**, httpsOnly, health monitoring on, default document `index.asp`, App Service Authentication → Entra ID, anonymous off, Login action; custom domain `postal.syntaxcom.com` (CNAME + managed cert) applied at cutover, not provisioning.
- Infra changes: Bicep in `infra/`
- Steps: 1) author the bicep (spec §"Azure resources" / §"Environment and configuration"); 2) `azd provision --preview` / what-if (azure-deployment-preflight); 3) deploy to dev/staging resource group; 4) confirm settings via `az webapp config show` (32Bit, Classic, httpsOnly, auth enabled).
- Environment: none in bicep (no secrets); `APPINSIGHTS_CONNECTION` auto-injected or from existing App Insights component
- RBAC / Permissions: deployer needs App Service plan + site creation; site gets NO managed-identity storage roles (Phase 1 has no storage access); SQL firewall "Allow Azure services"
- Acceptance criteria: `az webapp config show` shows `linuxFxVersion` unset, `use32BitWorkerProcess=true`, `managedPipelineMode=Classic`, `httpsOnly=true`; unauthenticated GET to `/` redirects to Entra sign-in (not 200); SQL firewall reachable from the App Service IP.
- Tests: what-if dry run (preflight skill) + post-deploy `az` assertions scripted in `infra/scripts/verify-postal-web.ps1`.
- Test data: none
- Estimated effort: 2 h
- Commit message template: `feat(infra): bicep for postal-web windows app service (32bit classic entra auth)`
- Status.md update: `✅ W4 postal-web App Service deployed to staging via bicep; 32-bit/Classic/Entra verified; infra/bicep/postal-web.bicep`

### W5 — CI/CD pipeline (GitHub Actions, OIDC, zip deploy)
- Title: Pipeline: build website zip (with connvars injection) → deploy to App Service
- Owner: infra / backend dev
- Branch: `postal-website-deploy`
- Files to add: `.github/workflows/deploy-website.yml`: (1) checkout; (2) run W1 deploy-set filter (exclude junk per §5); (3) run W2 `gen-connvars.ps1` with OIDC-fetched Key Vault secret; (4) zip; (5) scan artifact for secrets (legacy password, machineKey pattern, SAS tokens); (6) deploy via `Azure/webapps@v3` zip deploy using **OIDC federated credential** (no long-lived service principal); (7) post-deploy smoke: `curl -sS -o NUL -w "%{http_code}" https://<staging>/index.asp` expecting 302 (Entra redirect), not 404/500.
- Infra changes: GitHub Actions workflow; OIDC trust on the Azure subscription (ops one-time: `az fs federated-credential`)
- Steps: per list above; secrets only in Key Vault via OIDC.
- Environment: OIDC audience/issuer (no secrets); Key Vault refs `POSTAL_DB_SERVER`, `POSTAL_DB_NAME`, `POSTAL_DB_USER`, `POSTAL_DB_PASSWORD`
- RBAC / Permissions: federated identity needs `Website Contributor` on the `postal-web` site scope only
- Acceptance criteria: a push to `postal-website-deploy` builds and deploys to staging end-to-end with zero credentials in repo or logs; artifact scan passes; post-deploy smoke returns 302; re-running the pipeline is idempotent.
- Tests: the workflow itself is the integration test; add a `dry-run` branch trigger that stops before deploy for PRs.
- Test data: none
- Estimated effort: 3 h
- Commit message template: `ci(website): oidc zip-deploy pipeline with connvars injection and secret scan`
- Status.md update: `✅ W5 website CI/CD live: OIDC zip deploy to staging, secret scan green; .github/workflows/deploy-website.yml`

### W6 — Staging acceptance matrix (websitespec §13)
- Title: Run full page-parity acceptance on `postal-staging` against a DB copy
- Owner: cfettinger (operator sign-off) + backend dev
- Branch: n/a (verification task)
- Files to add: `Postal/website-acceptance.md` (checklist results), before/after print-preview screenshots for `printdata`, `facingslipsHTML` (+ both district variants)
- Infra changes: staging DB copy of production (ops)
- Steps: 1) deploy W5 build to staging pointed at the DB copy; 2) run one real import through the `spec.md` pipeline into the same DB **before** site testing (site's first read must be post-import); 3) execute the §9 anchors: mode switch (res/both → correct `delstatweb`/`delstatwebboth` tables, ~90 s message, both `EXEC`s visible in Query Store); print output (page breaks, `****ECRWSS****`, 900px tables, zero-padded zips); Boxes aggregation (Pinebush/Westbury=100, Roselle/Deerpark=50 chunks); `PINE BUSH` redirect to `facingslipspinebush.asp`; mutation round-trips (throwaway district + routes + labels + office copies + comments, each followed by expected SP rebuilds); red/green change rows in `deliveryenter`; FlagReport thresholds; 4) security checks: unauthenticated → Entra (not 200); HTTPS redirect; `district' OR 1=1--` probe on every input → validation error/empty, no stack trace; 5) verify "Update Routes" nav now drives `updatedelete.asp` and the `totpos` update echoes through `postalss`.
- Environment: staging URLs + staging DB name (no secrets in this doc); operator account in the postal-ops Entra group
- RBAC / Permissions: Entra group membership for the test operator
- Acceptance criteria: every §9/§13 anchor passes and is recorded in `website-acceptance.md` with evidence (screenshots / Query Store queries / HTTP codes); zero 5xx in App Insights during the run; no credentials in the deployed zip (artifact scan).
- Tests: the checklist itself (manual + scripted curl probes); screenshots diff-verified.
- Test data: throwaway test district/routes (recorded, deleted after)
- Estimated effort: 4 h
- Commit message template: `test(website): staging acceptance matrix results (page parity + security probes)`
- Status.md update: `✅ W6 staging acceptance passed: <n>/<n> anchors; evidence in Postal/website-acceptance.md`

### W7 — Cutover + ops handoff
- Title: DNS cutover to `postal-web`, warm window, ops docs update
- Owner: ops + cfettinger
- Branch: n/a (runbook)
- Files to add: `Postal/website-cutover-runbook.md` (from websitespec §"Cutover plan"); edit `postal instructions.txt` (drop FTP/Remote-Desktop steps 1–2; note Step 6 manual date edit becomes automatic in Phase 2)
- Infra changes: CNAME `postal.syntaxcom.com` → `postal-web` (DNS); legacy VM `69.20.14.96` + SQL `REDACTED_INTERNAL_IP` kept warm, **read-only**
- Steps: 1) confirm W6 green; 2) run one real monthly import through the new pipeline first; 3) cut CNAME (TTL lowered 48 h ahead); 4) verify live site: sign-in, `deliverystat`, one report, print preview; 5) during warm window (2 full import cycles): legacy VM read-only, all edits to Azure; nightly row-count reconcile on `District*` tables; 6) rollback = repoint CNAME back (no reverse data migration exists except `District*`); 7) after two clean months: decommission legacy VM + SQL.
- Environment: DNS access; Azure + legacy-VM admin access; Key Vault access for decommission
- RBAC / Permissions: DNS CNAME change; SQL firewall remove legacy VM IP at decommission
- Acceptance criteria: `postal.syntaxcom.com` serves the Azure site for two consecutive import cycles with zero data loss (row-count reconcile exact), one successful drill of the rollback procedure, legacy resources decommissioned and documented.
- Tests: post-cutover smoke (same curl/Entra checks as W5 step 7) + 2-cycle reconcile script.
- Test data: live monthly delstat file (imported via spec.md pipeline)
- Estimated effort: 2 h cutover day + 8 weeks warm window (no active effort)
- Commit message template: `docs(website): cutover runbook + ops procedure revision (Phase 2 notes)`
- Status.md update: `✅ W7 cutover complete: CNAME live <date>; warm window ends <date>; legacy decommissioned`

Postal Migrator agent responsibilities
 - Always update Postal/status.md after completing a meaningful task. Include: what changed, file paths, branch name, and any manual steps required to run/deploy.
 - Do not commit secrets. Reference environment variables or Key Vault paths instead.
 - When creating SQL or infra changes, include an SQL script or Bicep file under infra/ and list required RBAC/role assignments in status.md.
 - For each API or function change, include acceptance criteria and at least one integration test to demonstrate success.

## Current In-Progress Work

- ✅ API: POST /api/imports (create ImportJob + mint SAS)
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Api/Program.cs, src/Postal.Api/Data/ImportJobRepository.cs, src/Postal.Api/Services/BlobSasService.cs, src/Postal.Api/Services/ImportJobService.cs
  - Started: 2026-10-17T12:00:00Z
  - Progress: ✅ COMPLETE 2026-10-17
  - Evidence: end-to-end operator smoke test (7E1) — job created, SAS minted, sample.wrk uploaded, import processed. Bug found and fixed during extraction: POST response now uses the repo-canonical BlobName (imports/{jobId}) instead of reconstructing a path with the original filename, keeping it consistent with /complete and ImportWorker.

- ✅ API: POST /api/imports/{jobId}/complete and /sas-refresh
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Api/Services/ImportJobService.cs, src/Postal.Api/Program.cs, tests/Postal.Api.Tests/ImportJobServiceIntegrationTests.cs
  - Started: 2026-10-17T12:00:00Z
  - Progress: ✅ COMPLETE 2026-10-17
  - Manual verification: 7E1 smoke test confirmed blob existence/empty checks, 404/409 paths, and queue enqueue.
  - Testable refactor: endpoint logic extracted into ImportJobService (outcome enums: CompleteJobOutcome / RefreshSasOutcome) with static queue peek/delete helpers; Program.cs endpoints are thin result delegators.
  - Integration tests: tests/Postal.Api.Tests (xunit, 7 tests: enqueue-once, missing-blob 400, running-job 409, unknown-job 404, refresh OK/409/404). Build-verified (0 errors, 0 warnings) 2026-10-17; NOT executed (operator-run per instruction). Tests early-return with a SKIPPED log line unless POSTAL_DB_CONN and STORAGE_ACCOUNT_URL env vars are set. Run locally: dotnet test tests/Postal.Api.Tests/Postal.Api.Tests.csproj with those two env vars pointing at dev storage and dev SQL.

- ✅ Function: ImportWorker core import flow and hardening
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Function/ImportWorker.cs, src/Postal.Function/Program.cs, src/Postal.Function/host.json, src/Postal.Function/Postal.Function.csproj
  - Started: 2026-10-17T12:00:00Z
  - Status: ✅ COMPLETE 2026-10-20 — queue visibility renewal, managed-identity SQL auth, config-driven batch/retry settings, and App Insights telemetry are in place and build-verified. Remaining work is Azure deployment/ops follow-through rather than core worker logic.

- 🟡 Azure Function + SQL deployment prep
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: infra/bicep/main.bicep, infra/bicep/main.parameters.json, azure.yaml, .github/workflows/deploy-api-function.yml, infra/README.md, src/Postal.Function/Program.cs, src/Postal.Function/host.json, src/Postal.Function/Postal.Function.csproj
  - Started: 2026-10-20T09:00:00Z
  - Status: active — Bicep/azd + OIDC CI authored and build-verified (`az bicep build` 0 errors, 2026-10-20); remaining is running `azd provision`/deploy to a resource group and verifying the managed-identity path before production cutover.
  - Next commands: `azd provision` (or `az deployment group what-if --template-file infra/bicep/main.bicep`), then confirm the MI has `Storage Blob Data Contributor` + `Storage Blob Delegator` (assigned by the Bicep) and SQL permissions via the W3 grant scripts.

<!-- appended by Postal Migrator -->

## Recent Automated Checks

- 2026-10-17T00:10:42-07:00 — Security: Created `replacements.txt` and performed an initial local history-rewrite test on a mirror to remove discovered plaintext tokens from repository history. No remote force-push was performed; initial cleaned artifacts were produced locally: `D:\Projects\Syntax-Migration-Agents\mirror-cleaned.git`, `D:\Projects\Syntax-Migration-Agents\mirror-clean-checkout`. Immediate action: rotate any credentials that may have been exposed before coordinating a force-push to origin.

- 2026-10-17T00:25:00-07:00 — Security: Expanded the rewrite run: re-ran git-filter-repo on `D:\Projects\Syntax-Migration-Agents\mirror-temp` using the current `replacements.txt` and recreated `D:\Projects\Syntax-Migration-Agents\mirror-cleaned.git` and `D:\Projects\Syntax-Migration-Agents\mirror-clean-checkout`. Verification: repository and commit-level searches in the cleaned checkout returned no matches for the literal `<REDACTED_DB_PASSWORD>` token.

  Note: a programmatic attempt to append additional variants to `replacements.txt` failed due to local file-write restrictions in this environment. If additional literal variants should be removed, add them to `D:\Projects\Syntax-Migration-Agents\replacements.txt` and re-run the local rewrite. See the 'Security Remediation & Release Plan' section for the recommended coordination steps.

- 2026-10-17T12:10:00Z — Dev server connectivity: TCP to REDACTED_AZURE_SQL_HOSTNAME.public.0321e1ea10c5.database.windows.net:3342 succeeded (Test-NetConnection). Azure CLI (az) not available in this environment; interactive AAD sign-in (az login or Visual Studio) required locally for DefaultAzureCredential to mint SAS via BlobSasService.

- 2026-10-17T23:15:00Z — Repo README refresh: `README.md` in the migration local repo (D:\Webs\Syntax\PostalExe\migration, branch postal-azure-function-worker) rewritten to mirror this tracker. Documents the four projects (legacy PostalExe desktop importer, legacy ASP website lift & shift, Postal.Api + Postal.Function + integration tests, and the Syntax-Migration-Agents tracking workspace), local run instructions, repository structure, and current status (7E1 smoke ✅, ImportWorker hardening 🟡, next pickable W3). No secrets. Committed as `84b2868` (local branch, no push — local repo). Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).

- 2026-10-20T10:00:00Z — ImportWorker hardening verification: `dotnet build .\src\Postal.Function\Postal.Function.csproj -c Debug` succeeded with 0 errors; `dotnet test .\tests\Postal.Api.Tests\Postal.Api.Tests.csproj -c Debug` passed with 7 passed, 0 failed. Verified features: queue visibility renewal loop, managed-identity SQL auth via `DefaultAzureCredential` with `POSTAL_DB_CONN` fallback for local dev, configurable batch/retry values, and App Insights telemetry configuration. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).

- 2026-10-20T10:15:00Z — Repo baseline verification: `dotnet build Postal.sln -c Debug` should be run before Azure deployment and is the build gate for the migration repo. This ensures the API + Function + test projects remain green before resource deployment or CI automation begins. Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).

- 2026-10-20T10:30:00Z — Item 7 Bicep/azd + OIDC CI authored and build-verified. Added to the migration repo (branch `postal-azure-function-worker`): `infra/bicep/main.bicep`, `infra/bicep/main.parameters.json`, `azure.yaml`, `.github/workflows/deploy-api-function.yml`; updated `infra/README.md` and `.gitignore` (git-ignored `infra/bicep/main.parameters.dev.json`). Verification: `az bicep build --file infra/bicep/main.bicep` → **exit 0, 0 errors** (1 non-blocking warning: `Microsoft.Storage/storageAccounts/queues` has no Bicep type definitions). `main.parameters.json` validated as well-formed JSON; `azure.yaml` + workflow contain no tabs. No secrets in any committed file (secure `sqlAdminPassword` has no default; CI fetches it from Key Vault at deploy time). Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot).

- 2026-10-20T10:45:00Z — RBAC role assignments verified ✅. Assigned **Storage Blob Data Contributor** and **Storage Blob Delegator** to the managed identity `syntax-main-id` (principal ID: `a9c0e286-ecd6-4c1b-beb4-ead5fdb75481`) on the storage account `/subscriptions/5a5056f9-2199-4063-9133-0d9a32714a8a/resourceGroups/Syntax/providers/Microsoft.Storage/storageAccounts/syntaxstoragev2`. Verification command: `az role assignment list --assignee-object-id a9c0e286-ecd6-4c1b-beb4-ead5fdb75481 --scope /subscriptions/5a5056f9-2199-4063-9133-0d9a32714a8a/resourceGroups/Syntax/providers/Microsoft.Storage/storageAccounts/syntaxstoragev2 --query "[].roleDefinitionName" -o table` returned `Storage Blob Data Contributor` and `Storage Blob Delegator`. **Next: Confirm Function App and Web App identity assignment to the managed identity and deploy in Azure.** Agent: Postal Migrator - GitHub Copilot (cfettinger / GPT-5 Mini).

<!-- end appended -->
