# Syntax Migration Agents

A collection of agent specs and specifications for migrating legacy postal-delivery software from its legacy hosting/database stack to modern GitHub and Azure platforms.

## Contents

| Directory | Description |
|-----------|-------------|
| [`Postal/`](Postal/) | Migration spec for the legacy desktop import app (`Form1.vb`, VB.NET WinForms). Covers the target design: browser → Azure Blob Storage block upload, queue-based worker, Azure SQL bulk insert of the fixed-width `Delstat` import. See [`Postal/spec.md`](Postal/spec.md) for the full v1.2 specification and [`Postal/status.md`](Postal/status.md) — the live plan and progress tracker for the Postal implementation. |
| [`beanstalk-github/`](beanstalk-github/) | A portable agent prompt (`agent.md`) that walks a user through migrating a Beanstalk-hosted SVN repository to a GitHub Git repository. Targets VS Code (Copilot), Claude Code, and Hermes harnesses. |

## Postal migration — summary

- **Today:** a VB.NET WinForms app reads a ~209 MB (national) fixed-width file and inserts rows into `Delstat` via `System.Data.SqlClient`.
- **Target:** a .NET 8 web app on Azure App Service:
  - The browser uploads the file **directly** to Azure Blob Storage using a user-delegation SAS (block upload, no file body through App Service).
  - A queue-based worker streams the blob, parses the 309-byte records with the legacy field rules, and bulk-inserts into Azure SQL with checkpointed resume.
  - Job status (`Queued` / `Running` / `Succeeded` / `Failed`) and `RowsWritten` are surfaced via a small REST API.
- The spec covers SAS refresh for slow uploads, single-consumer leases, transient-fault retries, resume semantics, least-privilege managed-identity RBAC, and deployment via azd/Bicep.
- The Postal implementation is planned and tracked in [`Postal/status.md`](Postal/status.md), which is updated as tasks complete.

## Postal migration — projects & status

The Postal migration spans four projects. The implementation code lives in a
separate working repo (`D:\Webs\Syntax\PostalExe\migration`, branch
`postal-azure-function-worker`); this repo holds the specs and the live tracker.

| # | Project | What it is | Status |
|---|---------|-----------|--------|
| 1 | **Legacy PostalExe** (desktop importer) | VB.NET 2008 WinForms app (`Form1.vb`) that reads fixed-width Delstat `.wrk` files and loads `Delstat` via `System.Data.SqlClient`, then runs `Postalweb`/`Postalwebboth`. | Being replaced — behavior fully reproduced in the Function worker. |
| 2 | **Legacy Postal Website** (ASP classic) | IIS-hosted `.asp` site that displays/edits postal data. Lift & shift to Azure App Service (`postal-web`) with minimal code changes (deploy-time `connvars.asp`, `machineKey` removal, one nav fix). | W1 (page edits) + W2 (deploy-time connvars generator) done; W3 (SQL login `postalweb`) scripts authored. |
| 3 | **Postal.Api + Postal.Function** (.NET 8) | The new import pipeline: minimal API (import jobs + user-delegation SAS minting) + isolated queue-trigger worker (fixed-width/CRLF parse, chunked `SqlBulkCopy`, `RowsWritten` resume, SP calls). | API + Function complete and smoke-tested end-to-end (7E1). |
| 4 | **Tracking workspace** (this repo) | Multi-agent coordination: `Postal/spec.md` (importer design), `Postal/websitespec.md` (website lift & shift), `Postal/status.md` (live tracker). | Active — updated as tasks complete. |

### Running the new pipeline locally

1. Set env vars: `POSTAL_DB_CONN` (dev SQL) and `STORAGE_ACCOUNT_URL`
   (`https://<acct>.blob.core.windows.net`); optional `POSTAL_IMPORTS_CONTAINER`
   (default `imports`).
2. `dotnet run src/Postal.Api` — API on localhost.
3. `func start` in `src/Postal.Function` — Functions host.
4. `POST /api/imports` → PUT the `.wrk` to the returned SAS URL →
   `POST /api/imports/{jobId}/complete`.
5. Tests: `dotnet test tests/Postal.Api.Tests` (env-gated; skip without the vars).

### Infrastructure & CI (Item 7)

`infra/bicep/main.bicep` (+ `azure.yaml`) deploys the importer stack — Storage
(`imports` container + queue), App Service (API), Function App (worker), Azure
SQL, App Insights, and the system-assigned managed identity with **Storage Blob
Data Contributor + Storage Blob Delegator**. Deploy with `azd up`. CI
(`.github/workflows/deploy-api-function.yml`) uses OIDC (`azure/login@v2`) — no
long-lived credentials in the repo; the SQL admin password is fetched from Key
Vault at deploy time. See `infra/README.md` in the migration repo.

## Beanstalk → GitHub migration — summary

A step-by-step agent procedure using `git svn clone --stdlayout` (with `authors.txt` mapping) to convert a Beanstalk SVN repo to GitHub, preserving branches and tags and preferring SSH remotes. No credentials are ever written to files.
