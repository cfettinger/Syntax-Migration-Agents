# Legacy desktop import (Form1.vb) → Azure App Service + Blob + Azure SQL — Implementation Status

**Last Updated:** 2026-10-16  
**Spec Version:** 1.2  
**Implementation Phase:** Scaffolding / branch created (postal-azure-function-worker)

> This is a living tracker. Update it as tasks complete. The design spec lives in `spec.md`.

---

## Completed (✅)

## In Progress / Pending (🟡)

- Created migration scaffold at D:\Webs\Syntax\PostalExe\migration (new Git repo). Branch: postal-azure-function-worker (scaffolded minimal Api + Function projects).
- Next: implement API endpoints to create ImportJob and mint user-delegation SAS; implement Function worker parsing and DB claim logic.
## Open Design Decisions (from §12)

## Architecture Notes

## Databases (inventory & auth)

- Development (interactive): REDACTED_AZURE_SQL_HOSTNAME.public.0321e1ea10c5.database.windows.net,3342 — use AAD interactive authentication for local development. Set POSTAL_DB_CONN in your local environment for testing (do NOT commit). Example auth: Authentication=ActiveDirectoryInteractive; User ID shown only for reference; do not store passwords in repo.
- Production (managed): production SQL instance (managed by infra/ops). Runtime should use either managed identity (preferred) or a dedicated limited SQL account. Operations will retain the existing REDACTED_SQL_ADMIN SQL Server admin account; a new least-privilege DB user will be created for the app with INSERT on Delstat/ImportJob and EXECUTE on Postalweb & Postalwebboth. Credentials and any secrets must live in Key Vault or CI secret store — never checked into source.

Notes:
- Do not include passwords, SAS tokens, or keys in this file or in source. This file documents hostnames/auth patterns only.
- For local dev, use AAD interactive sign-in (az login or Visual Studio) so DefaultAzureCredential/Interactive auth works.


## Next Immediate Steps (Priority Order)

- Implement ImportJob schema and Data access; scaffold Sql scripts.
- Implement /api/imports POST, /api/imports/{jobId}/complete, and /api/imports/{jobId}/sas-refresh.
- Implement Azure Function worker: queue visibility renewal, conditional DB claim, blob streaming, fixed-width parser, batching + SqlBulkCopy, stored procedure execution.
- Add infra Bicep/azd templates and CI with OIDC.
