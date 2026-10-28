# Intranet Migration Status

Classic ASP Syntax Intranet → Azure App Service (`intranet-web` on `postal-web-plan`, RG `Syntax`)

Spec: [siwebspec.md](Postal/siwebspec.md)
Source: `D:\Webs\Syntax\syntaxintranet\trunk\web\`
Migration: `D:\Webs\Syntax\syntaxintranet\migration\web\`

## Phase 1 Tasks

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Copy production files to migration/web | ✅ Done | 62 ASP + 9 dirs; junk excluded |
| 2 | Create deploy-list.txt | ✅ Done | Lists all deploy entries |
| 3 | Fix `database.asp` (connvars include) | ✅ Done | ODBC → SQLOLEDB via connvars.asp |
| 4 | Fix `leadlog/database.asp` (connvars include) | ✅ Done | Same pattern |
| 5 | Fix `global.asa` (endsession.asp → logout.asp) | ✅ Done | Removed ASP.NET API call |
| 6 | Clean `Web.config` | ✅ Done | Stripped machineKey, debug, Windows auth, Detailed errors |
| 7 | Create `connvars.template.asp` | ✅ Done | SQLOLEDB template with tokens |
| 8 | Create `infra/web/gen-connvars.ps1` | ✅ Done | Renders connvars.asp from env vars |
| 9 | Create `infra/web/deploy-website-local.ps1` | ✅ Done | Stage → zip → az webapp deploy → smoke |
| 10 | Create SQL login `SyntaxIntranet` | ☐ Pending | Run against syntax-sql/SyntaxIntranet |
| 11 | Provision App Service `intranet-web` | ☐ Pending | On postal-web-plan, 32-bit, Classic pipeline |
| 12 | Set App Service Authentication (Entra ID) | ☐ Pending | Anonymous off |
| 13 | Deploy to staging | ☐ Pending | Run deploy-website-local.ps1 |
| 14 | Smoke test | ☐ Pending | All key pages return 200 |
| 15 | DNS cutover | ☐ Pending | After two clean cycles on legacy |

## Phase 2 Tasks (post-cutover)

| # | Task | Status | Notes |
|---|---|---|---|
| 16 | Parameterize all SQL queries (ADODB.Command) | ☐ Pending | 19 defects in catalog |
| 17 | Consolidate auth to SSO (REMOTE_USER) | ☐ Pending | Remove forms login |
| 18 | Fix stale links, remove dead code | ☐ Pending | |
| 19 | Decommission legacy server | ☐ Pending | |

## Deployment Commands

```powershell
# Generate connvars.asp (requires INTRANET_DB_* env vars or Key Vault access)
pwsh D:\Webs\Syntax\syntaxintranet\migration\infra\web\gen-connvars.ps1

# Full deploy (generates connvars, stages, zips, deploys, smoke tests)
pwsh D:\Webs\Syntax\syntaxintranet\migration\infra\web\deploy-website-local.ps1

# Deploy without regenerating connvars
pwsh D:\Webs\Syntax\syntaxintranet\migration\infra\web\deploy-website-local.ps1 -NoConnvars

# Deploy without smoke tests
pwsh D:\Webs\Syntax\syntaxintranet\migration\infra\web\deploy-website-local.ps1 -SkipSmoke
```

## Azure Resources

| Resource | Name | Location |
|---|---|---|
| App Service | `intranet-web` | RG `Syntax` |
| App Service Plan | `postal-web-plan` (Windows) | RG `Syntax` |
| SQL Server | `syntax-sql` | RG `Syntax` |
| SQL Database | `SyntaxIntranet` | on `syntax-sql` |
| SQL Login | `SyntaxIntranet` | least-privilege |
| Key Vault | `kvsyntax` | RG `Syntax` |
| Storage (if needed) | `syntaxstoragev2` / `syntaxstoragecontainer1` | RG `Syntax` |
