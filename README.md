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

## Beanstalk → GitHub migration — summary

A step-by-step agent procedure using `git svn clone --stdlayout` (with `authors.txt` mapping) to convert a Beanstalk SVN repo to GitHub, preserving branches and tags and preferring SSH remotes. No credentials are ever written to files.
