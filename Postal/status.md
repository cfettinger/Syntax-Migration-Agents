# Legacy desktop import (Form1.vb) → Azure App Service + Blob + Azure SQL — Implementation Status

**Last Updated:** 2026-10-16  
**Spec Version:** 1.2  
**Implementation Phase:** Scaffolding / branch created (postal-azure-function-worker)

> This is a living tracker. Update it as tasks complete. The design spec lives in `spec.md`.

---

## Completed (✅)

## In Progress / Pending (🟡)

- Created migration scaffold at D:\Webs\Syntax\PostalExe\migration (new Git repo). Branch: postal-azure-function-worker (scaffolded minimal Api + Function projects).
- IMPLEMENTATION IN PROGRESS: API endpoints for ImportJob and SAS minting (POST /api/imports) — in progress on branch postal-azure-function-worker (started by GitHub Copilot). Files: src/Postal.Api/Program.cs, src/Postal.Api/Data/ImportJobRepository.cs, src/Postal.Api/Services/BlobSasService.cs
- IMPLEMENTATION IN PROGRESS: API endpoints /api/imports/{jobId}/complete and /api/imports/{jobId}/sas-refresh — in progress on branch postal-azure-function-worker. Files: src/Postal.Api/Program.cs
- 7E1 Manual smoke test: generate sample.wrk and run end-to-end import
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: migration/testdata/generate_sample.ps1
  - Started: 2026-10-17T12:00:00Z
  - Status: In Progress — checking connectivity to dev SQL and Storage
## Open Design Decisions (from §12)

## Architecture Notes

## Databases (inventory & auth)

- Development (interactive): free-sql-mi-9929479.public.0321e1ea10c5.database.windows.net,3342 — use AAD interactive authentication for local development. Set POSTAL_DB_CONN in your local environment for testing (do NOT commit). Example auth: Authentication=ActiveDirectoryInteractive; User ID shown only for reference; do not store passwords in repo.
- Production (managed): production SQL instance (managed by infra/ops). Runtime should use either managed identity (preferred) or a dedicated limited SQL account. Operations will retain the existing syntaxAdmin SQL Server admin account; a new least-privilege DB user will be created for the app with INSERT on Delstat/ImportJob and EXECUTE on Postalweb & Postalwebboth. Credentials and any secrets must live in Key Vault or CI secret store — never checked into source.

Notes:
- Do not include passwords, SAS tokens, or keys in this file or in source. This file documents hostnames/auth patterns only.
- For local dev, use AAD interactive sign-in (az login or Visual Studio) so DefaultAzureCredential/Interactive auth works.


## Next Immediate Steps (Priority Order)

The steps below are written as isolated, testable tasks so an outside engineer or automation agent can pick them up and complete them. Each task includes acceptance criteria and required artifacts.

1) Implement ImportJob DB objects and deployment script
   - Files: infra/sql/001-create-importjob.sql (exists), add 002-create-delstat-schema.sql if Delstat DDL is required for testing.
   - Acceptance: script runs against dev DB without secrets and creates ImportJob table and necessary indexes.
   - Owner: infra / DBA

2) API: POST /api/imports (create job + return user-delegation SAS)
   - Implement in src/Postal.Api:
     - Validate payload { originalFileName, sizeBytes } and reject >10GB.
     - Insert ImportJob row (Status=Queued) using POSTAL_DB_CONN.
     - Mint user-delegation SAS scoped to blobName (imports/{jobId}/{originalFileName}) with Create+Write permissions, expiry <= 1h. Use DefaultAzureCredential and Storage SDK; requires STORAGE_ACCOUNT_URL and managed identity with Storage Blob Delegator role.
     - Return JSON: { jobId, blobName, sasUrl, expiresUtc }
   - Acceptance: end-to-end local test where API returns a valid SAS URL and a block upload (using azure/storage-blob client or az storage blob upload-batch with SAS) succeeds to the imports container.
   - Owner: backend dev

3) API: POST /api/imports/{jobId}/complete
   - Implement server-side check: confirm blob exists and SizeBytes > 0, ensure ImportJob.Status is Queued (409 if Running/Succeeded), set or ensure Queued and enqueue jobId into the imports queue exactly once.
   - Response: 200 OK or 409 conflict with descriptive error.
   - Acceptance: after uploading via SAS and calling /complete, a single queue message containing the GUID string is present in the imports queue.
   - Owner: backend dev

4) API: POST /api/imports/{jobId}/sas-refresh
   - Implement refresh to mint a replacement SAS for the same blob while job is still Queued and upload is in progress.
   - Acceptance: client can resume a blocked upload by obtaining a new SAS and completing upload blocks.
   - Owner: backend dev

5) Azure Function worker improvements (src/Postal.Function)
   - Ensure queue message format is jobId string. Current ImportWorker implements parsing and bulk insert.
   - Add visibility renewal: use Azure.Storage.Queues client to ReceiveMessages with long visibility and periodically UpdateMessageAsync to renew until job finishes or fails.
   - Switch DB auth to managed identity: acquire access token via DefaultAzureCredential and set SqlConnection.AccessToken for production. Keep POSTAL_DB_CONN for dev interactive testing.
   - Add configurable BatchSize, MaxRetries, and Telemetry to AppInsights. Ensure RowsWritten resume logic is resilient and truncate-only-on-first-run.
   - Acceptance: worker correctly claims job (conditional DB update), processes blob, writes Delstat, executes Postalweb procedures, and marks job Succeeded; telemetry logs jobId and counts.
   - Owner: backend dev

6) Testing & QA
   - Unit tests for parser functions (fixed-width vs CRLF), malformed record failure cases, and resume skipping logic.
   - Integration test: local Azurite or dev Storage account + dev DB to run an end-to-end import of a small sample file (include a sample delstat.wrk in /testdata).
   - Acceptance: automated test runs pass locally in dev environment and in CI.

7) Infra & CI
   - Add Bicep/azd templates for Storage (imports container + queue), App Service, Function App, and Azure SQL; include role assignment steps for managed identity (Storage Blob Data Contributor + Storage Blob Delegator) and SQL user provisioning script (run by ops).
   - CI: GitHub Actions with OIDC token-based login for deployments; secrets only for non-OIDC scenarios stored in repo secrets or Key Vault.
   - Acceptance: ability to deploy dev stack via CI without injecting long-lived credentials.

8) Documentation & Handoff
   - Update README.md with local dev steps, env vars, and how to run the API and Function locally (az login or VS sign-in required).
   - Update Postal/status.md with a short checklist for each task above as completed items are checked off.

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

Postal Migrator agent responsibilities
 - Always update Postal/status.md after completing a meaningful task. Include: what changed, file paths, branch name, and any manual steps required to run/deploy.
 - Do not commit secrets. Reference environment variables or Key Vault paths instead.
 - When creating SQL or infra changes, include an SQL script or Bicep file under infra/ and list required RBAC/role assignments in status.md.
 - For each API or function change, include acceptance criteria and at least one integration test to demonstrate success.

## Current In-Progress Work

- 🟡 API: POST /api/imports (create ImportJob + mint SAS)
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Api/Program.cs, src/Postal.Api/Data/ImportJobRepository.cs, src/Postal.Api/Services/BlobSasService.cs
  - Started: 2026-10-17T12:00:00Z
  - Status: core implementation complete; needs local validation against storage and DB.

- 🟡 API: POST /api/imports/{jobId}/complete and /sas-refresh
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Api/Program.cs
  - Started: 2026-10-17T12:00:00Z
  - Status: implemented; needs integration test to confirm queue enqueue and blob checks.

- 🟡 Function: ImportWorker core import flow
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: src/Postal.Function/ImportWorker.cs
  - Started: 2026-10-17T12:00:00Z
  - Status: parsing, batching, SqlBulkCopy and post-import procedures implemented. Remaining: queue visibility renewal and managed-identity Sql AccessToken (planned follow-up).

If you approve these steps I will implement the API SAS endpoints next and update status.md with progress entries as I work.
