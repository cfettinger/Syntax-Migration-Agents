---
name: intranet-migrator
description: Connvars.asp generation, deploy-list.txt staging logic, zip-deploy flow, smoke tests, and forms authentication (no AAD app registration) for Classic ASP SyntaxIntranet lift-&-shift to Windows App Service.
---

# Intranet Migrator Skill

## Connvars.asp Generation (SQLOLEDB via Environment Variables)

**Why**: Classic ASP cannot read App Service Connection String app settings (those surface to IIS/.NET only). Solution: render `connvars.asp` at deploy time from environment variables, never commit it, include it at top of each database.asp.

**Provider**: `SQLOLEDB` (built-in COM provider on Windows, no ODBC Driver 17 install).

**Template** (`web/connvars.template.asp`):
```asp
<%
' Do NOT commit this file. It is generated at deploy time via gen-connvars.ps1
' from environment variables: INTRANET_DB_SERVER, INTRANET_DB_NAME, INTRANET_DB_USER, INTRANET_DB_PASSWORD
ConnString = "Provider=SQLOLEDB;Data Source=tcp:<INTRANET_DB_SERVER>,1433;Initial Catalog=<INTRANET_DB_NAME>;"
DbUser = "<INTRANET_DB_USER>"
DbPassword = "<INTRANET_DB_PASSWORD>"
%>
```

**Generation** (`infra/web/gen-connvars.ps1`):
1. Read environment variables `INTRANET_DB_SERVER`, `INTRANET_DB_NAME`, `INTRANET_DB_USER`, `INTRANET_DB_PASSWORD`.
2. If password is missing, read from Key Vault:
   ```powershell
   $password = az keyvault secret show --vault-name kvsyntax --name syntaxintranet --query value -o tsv
   ```
3. Replace `<INTRANET_DB_*>` tokens in `connvars.template.asp`.
4. Write to `web/connvars.asp` (NOT committed; added to `.gitignore`).
5. Validate SQLOLEDB syntax (test connection string parse, no errors on double-quote or semicolon).
6. Return generated file path and mask password in console output.

**Usage in database.asp**:
```asp
<%
  ' At top of file, include connvars.asp
  '<!--#include file="connvars.asp"-->
  
  ' Later, open connection
  Set conn = CreateObject("ADODB.Connection")
  conn.Open ConnString, DbUser, DbPassword
  
  ' Use conn for queries
  Set rs = conn.Execute("SELECT * FROM myTable")
  ' ...
  conn.Close
  Set conn = Nothing
%>
```

**Environment Variable Setup** (for deploy):
- `INTRANET_DB_SERVER=syntax-sql.database.windows.net`
- `INTRANET_DB_NAME=SyntaxIntranet`
- `INTRANET_DB_USER=syntaxintranet`
- `INTRANET_DB_PASSWORD=<fetched-from-kvsyntax>` (process env var only, never printed)

---

## Deploy-List.txt Staging Logic

**Purpose**: Declaratively specify which files / directories must be deployed to Azure App Service.

**Format** (`deploy-list.txt`):
```
# Comment lines start with #
# Empty lines are ignored

# ASP pages (root)
default.asp
stafflogin.asp
checklogin.asp
logout.asp
reports.asp
# ... (one per line)

# Subdirectories (with -Recurse flag during copy)
includes/
scripts/
images/
css/
data/
leadlog/
```

**Staging Process** (in `deploy-website-local.ps1`):
1. Read `deploy-list.txt`, strip comments and empty lines.
2. For each entry:
   - If it's a file: copy single file from `web/` to staging folder.
   - If it's a directory: `Copy-Item -Path "web/<dirname>" -Destination "staging/<dirname>" -Recurse -Force`.
3. **Ensure parent directories exist**: before each subdirectory copy, run:
   ```powershell
   New-Item -ItemType Directory -Path "staging/<dirname>" -Force | Out-Null
   ```
4. After all entries staged, copy generated `connvars.asp` to staging root:
   ```powershell
   Copy-Item -Path "web/connvars.asp" -Destination "staging/connvars.asp" -Force
   ```
5. Verify staging folder has all expected files (count against deploy-list entries).

**Purpose of deploy-list.txt**: 
- Explicit whitelist of what goes to Azure (avoids shipping Thumbs.db, .git, IDE files, etc.).
- Makes deployment reproducible; easy to audit what's live.
- Supports incremental cleanup (remove entries from list to prune files).

---

## Zip-Deploy Flow

**Workflow**:
1. **Stage**: Copy deploy-list.txt entries + connvars.asp into a temp folder.
2. **Validate**: Verify expected file counts; check connvars.asp is present and valid.
3. **Zip**: Create a .zip archive of the staged folder.
   ```powershell
   Compress-Archive -Path "staging/*" -DestinationPath "deploy.zip" -Force
   ```
4. **Deploy**: Push to App Service via `az webapp deploy`:
   ```powershell
   az webapp deployment source config-zip `
       --resource-group Syntax `
       --name intranet-web `
       --src-path "deploy.zip"
   ```
5. **Monitor**: Check deployment status (OneDeploy may take 1–5 min).
   ```powershell
   az webapp deployment list-publishing-profiles --resource-group Syntax --name intranet-web
   ```
6. **Smoke Test**: After deploy completes, verify key pages (see Smoke Tests section below).

**OneDeploy Behavior**:
- OneDeploy **fully replaces** site/wwwroot. Any file NOT in deploy.zip is deleted.
- If connvars.asp is missing, all database.asp includes will fail (hard error on first page load).
- No rollback; previous version is gone. Keep a backup of .zip if rollback is needed.

---

## Smoke Tests

**Goal**: After deploy, verify the site is alive and serving pages without errors.

**Test Cases** (in `deploy-website-local.ps1`):

| Page | Expected HTTP | Expected Body | Notes |
|------|---|---|---|
| `https://intranet-web.azurewebsites.net/default.asp` | 200 | No error | Main page |
| `https://intranet-web.azurewebsites.net/stafflogin.asp` | 200 | No error | Login form |
| `https://intranet-web.azurewebsites.net/leadlog/` | 200 or 302 | No error | May redirect to login |
| `https://intranet-web.azurewebsites.net/reports/` | 200 or 302 | No error | May redirect to login |

**Smoke Test Script**:
```powershell
$testUrls = @(
    "$BaseUrl/default.asp",
    "$BaseUrl/stafflogin.asp",
    "$BaseUrl/leadlog/",
    "$BaseUrl/reports/"
)

foreach ($url in $testUrls) {
    try {
        $response = Invoke-WebRequest -Uri $url -SkipHttpErrorCheck
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 302) {
            Write-Host "✓ $url : $($response.StatusCode)"
        } else {
            Write-Host "✗ $url : $($response.StatusCode)" -ForegroundColor Red
            $failed = $true
        }
        # Optionally check for error keywords
        if ($response.Content -match "error|exception|fatal" -and $response.StatusCode -eq 200) {
            Write-Host "⚠ $url : possible error in response body" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "✗ $url : $_" -ForegroundColor Red
        $failed = $true
    }
}

if ($failed) {
    Write-Host "Smoke tests FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "Smoke tests PASSED" -ForegroundColor Green
}
```

**Debugging Failed Tests**:
- Check App Service logs via Azure Portal (App Service → Log stream).
- SSH into App Service (`az webapp ssh --resource-group Syntax --name intranet-web`) and inspect `D:\home\site\wwwroot\` for connvars.asp and key .asp files.
- Test database connection: create a simple test.asp page that opens a connection and prints schema info.

---

## Forms Authentication (Single-Layer Model)

**Decision 2026-10-28:** No AAD app registration is created. App Service Authentication is set to **Allow Anonymous** (disabled). The classic ASP forms login (`stafflogin.asp` → `checklogin.asp`) is the **sole authentication gate**.

### How It Works
1. User navigates to any page on `intranet-web.azurewebsites.net`.
2. If `Session("accesslevel")` is not set, the page redirects to `stafflogin.asp`.
3. `stafflogin.asp` presents a username/password form.
4. `checklogin.asp` validates credentials against the database and sets:
   - `Session("accesslevel")` = "A" (admin) or "E" (employee)
   - `Session("employeeid")` for row-level filtering
5. All pages gated by `database.asp`: if session is not "A" or "E", redirect to `Default.asp`.

### Phase 2: Consolidate to SSO (future, optional)
- Replace `stafflogin.asp` / `checklogin.asp` with a single sign-on page that reads `REMOTE_USER` from Entra ID.
- Looks up the employee record by UPN/email and sets `Session("accesslevel")` without a second password prompt.
- This requires creating an AAD app registration at that time.

---

## Status Tracking

Always update `Intranet/INTRANET_STATUS.md` in the Syntax-Migration-Agents repo (via the local path the user provides) after meaningful progress. Do not rely on the currently open solution for that file.

**Status field meanings**:
- ✅ Done: Task completed and verified (all acceptance criteria met).
- 🔄 In Progress: Task started; may have partial results.
- ☐ Pending: Not yet started.
- 🚫 Blocked: Cannot proceed due to a dependency or external blocker; note the reason.

**After each session**, update the summary row at the top of INTRANET_STATUS.md with the Agent Identifier and timestamp:
```
Last Update: Intranet Migrator - GPT-5 Mini (cfettinger / GitHub Copilot) — 2025-01-15 14:30 UTC
```

---

**Source of Truth**: `<path-to-Syntax-Migration-Agents>/Intranet/siwebspec.md`  
**Live Tracker**: `<path-to-Syntax-Migration-Agents>/Intranet/INTRANET_STATUS.md`
