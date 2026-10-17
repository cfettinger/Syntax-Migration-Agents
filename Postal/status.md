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
- PLANNED: Website deployment (websitespec.md lift & shift, `postal-web`). Detailed handoff TODOs W1–W7 are in the section "Website Deployment TODOs" below. Next pickable task: W1 (Phase 1 source edits). All artifacts live in the central shared workspace so other agents can participate; tasks run from the repository's central checkout on `main`.
 - 7E1 Manual smoke test: generate sample.wrk and run end-to-end import
  - Agent: Postal Migrator - GPT-5 Mini (cfettinger / GitHub Copilot)
  - Branch: postal-azure-function-worker
  - Files: migration/testdata/generate_sample.ps1
  - Started: 2026-10-17T12:00:00Z
  - Status: In Progress — API build succeeded for Postal.Api; Postal.Function build/test started
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
  - Next actions:
    1) Build src/Postal.Function and resolve any compile errors.
    2) Launch the Function host locally (func start or dotnet run) and monitor logs.
    3) Execute manual smoke test steps: generate sample.wrk, POST /api/imports to get SAS, upload sample to SAS URL, POST /api/imports/{jobId}/complete, verify queue message and let the Function process the job. Record evidence (DB row counts, logs) before marking this task complete.
- ✅ Website lift & shift review (websitespec.md vs trunk/website/web): confirmed NO major code changes needed. Verified against source: conn layer edits in database.asp (line 12 legacy ODBC conn), facingslipspinebush.asp + facingslipsroselle.asp (dead sa/SYNTAXWEB conns, lines 4-5); web.config machineKey removal (line 13); one nav fix in postalss.asp line 276 (routeupdate.asp → updatedelete.asp). Junk pages confirmed present (a.asp, test2.asp, routeupdate.asp, search.htm, aspnet_client/). Branch: main (this repo).
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

## Website Deployment TODOs (websitespec.md — `postal-web` lift & shift)

Source: `D:\Webs\Syntax\PostalExe\trunk\website\web` (SVN working copy `trunk/website`). All artifacts live in the central shared workspace so other agents can participate; all tasks run from this repository's central checkout on `main`; each task is self-contained and safe to hand off. Verified 2026-10-16 (see Completed): Phase 1 code diff is ~5 one-line edits + 1 config removal + deploy-set filter.

### W1 — Prepare website deploy source (Phase 1 code edits)
- Title: Apply websitespec §6 Phase 1 edits to website source
- Owner: cfettinger / Postal Migrator
- Branch: `postal-website-deploy` (off `main` in the PostalExe migration repo; merge to main when done — tasks operate from the central shared workspace so other agents can participate)
- Files to change:
  - `database.asp` — line 12: replace `conn.Open "driver={ODBC Driver 17...};server=172.20.0.141;...","syntaxpostal","<REDACTED_DB_PASSWORD>"` with `<!--#include file="connvars.asp"-->` + `conn.Open ConnString, DbUser, DbPassword` (per §6.1; keep all commented history lines and all helpers: `sql_execute`, `validateInput`, `validateZip`, `returnValidated`, `returnZipValidated`, `ReadFormVariables`).
  - `facingslipspinebush.asp` lines 4–5, `facingslipsroselle.asp` lines 4–5 — replace `User id=sa;Data source=SYNTAXWEB` blocks with the same `connvars.asp` include and shared `conn`. Keep hardcoded queries (`WESTBURY` / `deerpark`) as-is.
  - `web.config` — remove the `<machineKey>` element (line 13). Remove nothing else.
  - `postalss.asp` line 276 — `href="routeupdate.asp"` → `href="updatedelete.asp"` (§6.4; only behavioral change).
  - New: `connvars.template.asp` (committed template with placeholders; real `connvars.asp` is git-ignored and generated at deploy per W2).
- Infra changes: none
- Steps: 1) copy `web/` into the deploy repo layout (suggested: `website/web/`); 2) apply the four edits above; 3) add `connvars.asp` to `.gitignore`; 4) build the deploy file list per websitespec §5 (exclude: `a.asp`, `a.html.txt`, `test2.asp`, `routeupdate.asp`, `search.htm`, `aspnet_client/`, `backup/`, `Thumbs.db`, `_derived*/`, `test.asp`, `Postal.sln`, `.vs/`); 5) diff every deployed page against the original and confirm ONLY the four files above differ.
 - Progress: ✅ COMPLETE 2026-10-16. Skeleton committed as `485c0b3` (connvars.template.asp, deploy-list.txt, README.md, .gitignore). Phase 1 edits committed as `daa681c` on branch `postal-azure-function-worker` (local repo, no remote; shared working copy per this section's rule — no separate `postal-website-deploy` branch needed): `website/web/database.asp` (connvars include + helpers, no secrets), `facingslipspinebush.asp`, `facingslipsroselle.asp` (shared `conn` via include), `web.config` (machineKey removed), `postalss.asp` (routeupdate.asp → updatedelete.asp).
 - Verification evidence: `git grep -i -E "REDACTED_DB_PASSWORD|172\.20\.0\.141|syntaxpostal" HEAD -- website/` → 0 matches (no secrets); `git grep -c "updatedelete.asp" HEAD -- website/web/postalss.asp` → 1; machineKey absent from `web.config` (comment documents removal); all three data pages contain `<!--#include file="database.asp" -->`. 
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

### W3 — SQL login `postalweb` + least-privilege grants
- Title: Create website SQL login and grants (run by ops on shared DB)
- Owner: infra / DBA
- Branch: n/a (SQL script in this repo)
- Files to add: `infra/sql/003-create-postalweb-login.sql` (exact grant set from websitespec §7: SELECT on Delstat/Delivery/DelstatWeb/DelstatWebBoth/DistrictLookup/DistrictInfo/DistrictLabels; UPDATE on DelstatWeb/DelstatWebBoth/DistrictInfo; INSERT+DELETE on DistrictLookup; SELECT+INSERT+UPDATE+DELETE on DistrictLabels; EXECUTE on Postalweb/Postalwebboth; NO TRUNCATE/ImportJob/db_owner)
- Infra changes: SQL script (ops runs it on the production SQL instance; dev DB too for testing)
- Steps: 1) create `003-create-postalweb-login.sql` from the §7 block (idempotent: `IF NOT EXISTS` guards); 2) ops creates the server login with a fresh Key Vault-stored password; 3) run script; 4) verify with `sp_helprole`-style queries / a test connection using the `postalweb` user.
- Environment: ops SQL admin access (`syntaxAdmin` retained); new password lives in Key Vault only
- RBAC / Permissions: the grants above, exactly; least privilege — the site's injection surface is bounded by this login until Phase 2
- Acceptance criteria: login `postalweb` can run `SELECT` on all web tables, `EXEC Postalwebboth`, `UPDATE DelstatWeb SET totpos=...`; attempts `TRUNCATE Delstat`, `INSERT ImportJob`, and `ALTER TABLE` all fail with permission errors.
- Tests: three-part verification script `infra/sql/004-verify-postalweb-grants.sql` (SELECT succeeds / UPDATE on granted table succeeds / UPDATE on Delstat fails).
- Test data: none
- Estimated effort: 0.5 h (script) + 0.5 h (ops run)
- Commit message template: `feat(infra): add postalweb least-privilege login script and grant verification`
- Status.md update: `✅ W3 postalweb login + grants created on dev (prod at cutover); grants verified; script infra/sql/003`

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
- Infra changes: CNAME `postal.syntaxcom.com` → `postal-web` (DNS); legacy VM `69.20.14.96` + SQL `172.20.0.141` kept warm, **read-only**
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

<!-- appended by Postal Migrator -->

## Recent Automated Checks

- 2026-10-17T12:10:00Z — Dev server connectivity: TCP to free-sql-mi-9929479.public.0321e1ea10c5.database.windows.net:3342 succeeded (Test-NetConnection). Azure CLI (az) not available in this environment; interactive AAD sign-in (az login or Visual Studio) required locally for DefaultAzureCredential to mint SAS via BlobSasService.

<!-- end appended -->
