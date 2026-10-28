# Spec: Classic ASP Syntax Intranet website (`trunk` → Azure App Service Windows, lift & shift)

Version 1.1, 2026-10-28 (v1.1: reviewed against actual source — populated page inventory, fixed §6.1 connection pattern, added Web.config specifics, identified 5 new defects #15–#19, confirmed Azure resources: `postal-web-plan`, `syntax-sql/SyntaxIntranet`)

Companion to `spec.md` (desktop importer → .NET 10). This spec covers the operator-facing intranet site at `trunk/` (**Classic ASP / VBScript / ADODB** on IIS).

> **Source note:** the working copy lives at `D:\Webs\Syntax\syntaxintranet\trunk`. The migration output directory is `D:\Webs\Syntax\syntaxintranet\migration`. Export the working copy fresh at implementation time so no local edits are lost.

## Goal

Move the existing ASP website to Azure **with a lift & shift, not a rewrite**: host the VBScript pages as-is in a Windows App Service, fix the connection layer, strip dead/junk files, add authentication, and point everything at the same Azure SQL database specified in `spec.md`.

1. A Windows App Service (`intranet-web`) serves the site at its custom domain (HTTPS-only).
2. All pages keep their current URLs, form names, and printed output byte-for-byte in intent.
3. Database access goes to the shared **Azure SQL** database via a new least-privilege SQL login; no credentials in source.
4. Phase 2 (after cutover) retires the legacy hosting without changing what operators see.

This follows the hosting findings: **Classic ASP + VBScript + ADODB runs on Azure App Service (Windows)** out of the box — ADODB is a built-in Windows COM component, no DLL registration needed, which is exactly what this site requires (no custom COM; desktop-bit executables are out of scope here).

## Non-goals

- **No rewrite to .NET 10 / C# / MVC.** Converting the site's ASP pages to Razor is a later, optional project; this spec deliberately keeps them in VBScript.
- No changes to printed/facing-slip layouts, page-break behavior, or report wording.
- No redesign of image-button navigation (Dreamweaver `MM_swapImage` gifs stay).
- Do not modify black-box stored procedures used by the site (owned by `spec.md`'s database migration).
- Do not port test/experiment pages, IIS text-search pages, or `backup/` into production.
- No file uploads **in Phase 1**: this site only reads/writes the database, so it needs no queue and no worker. If an upload feature is ever added to the classic site, follow §6.5 — files never land on `wwwroot` or `Path.GetTempPath()`, and the storage account reused is the one `spec.md` already provisions.

## Hosting decision

| Option | Verdict | Reason |
|---|---|---|
| **A. Windows App Service, site deployed as-is to `wwwroot`** | **Chosen** | The stack is supported on Azure App Service (Windows); lowest risk; zero code logic changes beyond §6; ADODB/SQLOLEDB built in. |
| B. Windows container with IIS | Rejected | Only needed for custom COM registration; none exist here. |
| C. Windows VM re-hosted IIS | Rejected | Defeats the migration; keep only as rollback during cutover. |
| D. Rewrite to .NET 8 MVC | Deferred | High effort, high regression risk on 20+ page-flows incl. print formatting; do it only if the site later needs scale-out, auth-by-role, or CI test coverage. |

One note that does **not** apply: "use Connection strings app settings for the database". Classic ASP **cannot read App Service connection-string settings** (they surface to IIS/.NET only). The connection string therefore travels via a generated include file (§6.1). Everything else in that guidance applies: Windows (not Linux) plan, **32-bit platform**, **Classic managed pipeline**, Basic B1 or higher, firewall "Allow Azure services", SQLOLEDB provider string.

## Azure resources (delta vs `spec.md`)

`spec.md` already provisions App Service (importer), Storage, Azure SQL, managed identity, Key Vault, App Insights. This spec **adds one resource and one service principal/login**:

> **Azure AI Services / Foundry note (future work):** Subscription `5a5056f9-2199-4063-9133-0d9a32714a8a` is eligible to upgrade from **AI Services Free Tier** to **Tier 1**. This is informational and does not change the intranet lift-and-shift plan, but it enables optional future **Azure AI Foundry Agent** additions (operator help/automation) under the same subscription.

- **App Service `intranet-web`** — Windows, .NET 4.8 runtime stack (stack is irrelevant beyond "Windows"; pick .NET 4.8), on plan **`postal-web-plan`** (existing Windows plan in RG `Syntax`). Configuration:
  - **Platform: 32 Bit; Managed pipeline: Classic**; HTTPS-only enabled; Application health monitoring on; Pre-/post-compilation handlers unused.
  - **Authentication: Entra ID (App Service Authentication)**, "Allow unauthenticated users = No" (§10).
  - Custom domain (CNAME) with App Service-managed certificate.
- **New SQL login `syntaxintranet`** in the shared database (§7). The importer's identity from `spec.md` is unchanged.
- **App Insights** — reuse; the site's failures (500s, ADODB errors) land in the same component or a second one. Alert on 5xx spikes.
- Storage account: **none in Phase 1**. No queue, no Function. If the §6.5 upload add-on is enabled, reuse `syntaxstoragev2` (container `syntaxstoragecontainer1`) — do not create a second one.

## Source inventory and cleanup

Working copy: `trunk/web/`. Migration output: `D:\Webs\Syntax\syntaxintranet\migration\web\`.

**Deploy (as-is):** All production `.asp` pages (62 files), `global.asa`, `styles.css`, `Web.config` (edited per §6.2), and supporting directories: `css/`, `images/`, `includes/`, `dropdown/`, `calendar/`, `announcements/`, `expense/`, `leadlog/`, `scripts/` (selective — see deploy-list.txt).

**Move to `/_archive/` (do not deploy; keep in repo for reference):**
- `test.asp` — scratch/debug page
- `staging_temp.asp` — staging experiment
- `slacker.asp`, `slacker list.doc`, `slacker.doc` — personal/junk
- `party.html`, `taglit-brithright.html`, `template.html` — personal/unused HTML
- `index.html` — superseded by `index.asp`
- `viewmiles_old.asp` — old version
- `leadlog/*_old.asp` (5 files) — old versions
- `leadlog/test.asp` — test page
- `avalon4/` — personal family page (glenn, kid, nicole, paul)

**Do not deploy at all:**
- `.vs/` (IDE), `aspnet_client/` (auto-generated .NET runtime), `_derived/` (build artifacts)
- `Thumbs.db` (all instances)
- `search.htm` (IIS 4-era text search webbot)
- `files.txt` (file listing, not a web asset)
- `Web.config.local`, `Web.config.production` (config variants)
- `scripts/jquery-ui-1.10.3.custom/development-bundle/` (dev docs/demos, ~200 files)
- `scripts/jquery-ui-1.10.3.custom/index.html`

## Phase 1 code changes (small, mechanical)

### 6.1 Database connection — `database.asp` (server-side include used by every page)

`database.asp` is the **single include** every page pulls in. It contains:
- The `conn.Open` call (hardcoded credentials)
- Access-level gate (`Session("accesslevel")` must be `"A"` or `"E"`, else redirect to `Default.asp`)
- Helper functions: `getAccessLevel()`, `ReadFormVariables()`, `validateInput()`, `validateZip()`, `returnValidated()`, `returnZipValidated()`

Today (line 8, active connection):
```asp
conn.Open "driver={ODBC Driver 17 for SQL Server};server=172.20.0.141;database=SyntaxIntranet","syntaxintranet","xXw8s7-n383a"
```
(Commented history: `chase\chase/syntaxleadlog`, `208.112.84.42/SyntaxIntranet`, `172.20.0.210/SyntaxIntranet`, `192.168.1.124/SyntaxIntranet`.)

**Change to:**
```asp
<!--#include file="connvars.asp"-->
conn.Open ConnString, DbUser, DbPassword
```

`connvars.asp` is **generated at deploy time** by the CI/CD pipeline from Key Vault secrets — never committed to source. It defines `ConnString`, `DbUser`, `DbPassword` using **SQLOLEDB** (built-in on Windows App Service; ODBC Driver 17 is NOT installed):

```asp
<%
ConnString = "Provider=SQLOLEDB;Data Source=tcp:syntax-sql.database.windows.net,1433;Initial Catalog=SyntaxIntranet;"
DbUser = "syntaxintranet"
DbPassword = "<generated-from-keyvault>"
%>
```

**Also fix `leadlog/database.asp`** — the leadlog sub-app has its own `database.asp` with a separate hardcoded connection. Apply the same `connvars.asp` include pattern there.

### 6.2 `Web.config` cleanup

Strip:
- `<machineKey validationKey="C47DAAA0..." decryptionKey="D7011F47..." />` — leaked hardcoded keys (line 73).
- `<authentication mode="Windows"/>` — irrelevant for Classic ASP; App Service Authentication (Entra ID) handles auth at the platform level. Remove or set to `None`.
- `<compilation debug="true">` — set to `debug="false"` for production.
- `<httpErrors errorMode="Detailed"/>` — change to `errorMode="Custom"` to hide stack traces.
- .NET 3.5 assembly references, `httpHandlers`, `httpModules`, `system.codedom` — not needed for Classic ASP; remove to reduce surface area.

Keep:
- `<defaultDocument>` with `index.asp` first (correct).
- `<pages enableSessionState="true" />` (ASP sessions depend on this).
- `<validation validateIntegratedModeConfiguration="false"/>` (prevents IIS config validation errors).

### 6.3 App Service configuration

Set these **application settings** on `intranet-web`:

| Setting | Value |
|---|---|
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Auto-injected by App Insights integration (or set manually). |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `false` (no build step for Classic ASP). |

Set these **general settings** on `intranet-web`:

| Setting | Value |
|---|---|
| **Always On** | `true` (keeps app warm, prevents cold starts) |
| **SCM type** | `None` (Basic Auth Publishing Credentials = false; use local git or zip deploy only) |
| **Default document** | `index.asp` (configured via `<defaultDocument>` in `Web.config`, §6.2) |

No connection-string app settings — classic ASP cannot read them. The connection string lives in the generated `connvars.asp`.

### 6.4 Navigation fixes

Audit all navigation links (`nav.html`, inline links) for:
- Hardcoded legacy server URLs → make relative or use the Azure domain during staging.
- Links pointing to archived/junk pages (e.g., CDO email test pages masquerading as real features).

### 6.5 File-upload-to-blob path (only if an upload feature is added)

Phase 1 ships without uploads. If the classic site later gains an upload feature:

- **Durability rule:** on App Service only the site content path is durable (Windows: `D:\home\site\wwwroot\...`). `Path.GetTempPath()` and anything outside it are wiped on restart or scale-out. **Never treat `wwwroot` as the archive** — it is the site and a poor store. Target is always a blob.
- **Rejected pattern:** ASP writes the file to disk, then a WebJob/timer Function copies it to the container and deletes the local copy. Race-prone, and the file briefly lives on the instance.
- **Recommended pattern: post the form to a small ASP.NET endpoint** that receives the `IFormFile`, calls `BlobClient.UploadAsync(stream, overwrite:)`, and **returns the blob URL** for the `.asp` page to store.
- **Pure-VBScript alternative (one file field only):** PUT the bytes straight to a SAS blob URL from the page, no local disk, using `MSXML2.ServerXMLHTTP.6.0`. The SAS needs **`cw` (create, write)** and must be short-lived (mint per-request from the importing app's managed identity). Store the **blob URL** in the database, never the SAS.

## Data and permissions

Shared Azure SQL database (per `spec.md`). The website touches its own set of tables and stored procedures.

Login `syntaxintranet` (SQL-user, not the importer's identity — isolates the site's write surface):

| Table / object | Grant |
|---|---|
| *(Populate from actual source inventory)* | SELECT |
| Tables requiring updates | SELECT, UPDATE |
| Tables requiring inserts/deletes | SELECT, INSERT, DELETE |
| Stored procedures used | EXECUTE |
| `ImportJob`, `Delstat` DML, `TRUNCATE`, `db_owner` | **not granted** |

```sql
-- Template: populate with actual table/procedure names from the site's source
CREATE USER [syntaxintranet] FOR LOGIN [syntaxintranet];
GRANT SELECT ON dbo.<table1>, dbo.<table2> TO [syntaxintranet];
GRANT UPDATE ON dbo.<table3> TO [syntaxintranet];
GRANT INSERT, DELETE ON dbo.<table4> TO [syntaxintranet];
GRANT EXECUTE ON dbo.<proc1>, dbo.<proc2> TO [syntaxintranet];
```

This least-privilege set **contains the blast radius** of any remaining SQL injection (§8) if Phase 2 slips: an attacker cannot truncate core tables or write `ImportJob`, and only the enumerated DML surfaces exist.

## State model

Legacy state, all of it:

| State | Where | Used by | Migration |
|---|---|---|---|
| `Session("accesslevel")` = `"A"` (admin) / `"E"` (employee) | ASP session | `database.asp` gate (redirect if not A/E); nav includes branch on role | **Keep `intranet-web` at 1 instance in Phase 1** (in-process session is fine). If scale-out is ever needed: configure SQL/Redis session state. |
| `Session("employeeid")` | ASP session | Set at login; used by `database.asp` (`Cint(Session("employeeid"))`) and most data pages for row-level filtering | Same as above. |
| Client-side nav state | JS in every page | nav highlights | Keep as-is. |

## Page inventory (role verified against source)

Disposition: **K** = deploy unchanged, **K+** = deploy with the §6 edits only, **A** = archive.

| Page | Role (verified) | Disp. | Notes / drift warnings |
|---|---|---|---|
| `Default.asp` | Login gate; checks `Session("accesslevel")`, redirects to `stafflogin.asp` if unset | K+ | Entry point after auth |
| `stafflogin.asp` | Login form (username/password → DB check) | K+ | Phase 2: replace with Entra ID SSO |
| `checklogin.asp` | Validates credentials against DB, sets session | K+ | SQL injection risk (Phase 2) |
| `checkfirstlogin.asp` | First-login password change flow | K+ | |
| `logout.asp` | Clears session, redirects to login | K+ | |
| `index.asp` | Main dashboard/home after login | K+ | |
| `index1.asp`, `index2.asp` | Alternate dashboard views | K+ | Verify which is linked from nav |
| `admin.asp` | Admin panel (user management entry) | K+ | |
| `useradmin.asp` | User CRUD (add/edit/delete employees) | K+ | |
| `useradminupdate.asp` | Saves user changes | K+ | |
| `nav.asp` | Main navigation include (role-based) | K+ | |
| `navAdmin.asp` | Admin nav include | K+ | |
| `navEmployee.asp` | Employee nav include | K+ | |
| `navLocal*.asp` (8 files) | Sub-section nav includes (Admin, Client, Expense, Job, Miles, Time, UserAdmin) | K+ | |
| `addclient.asp` / `editclient.asp` / `saveclient.asp` / `validateclient.asp` / `chooseclient.asp` / `clientlist.asp` | Client CRUD | K+ | |
| `addjob.asp` / `editjob.asp` / `savejob.asp` / `listjobs.asp` | Job CRUD | K+ | |
| `dailyjoblist.asp` / `dailyviewall.asp` | Daily job views | K+ | |
| `displayview.asp` / `displayview_t2c.asp` | Job detail views | K+ | |
| `print_displayview_t2c.asp` / `print_schedule.asp` | Print views | K+ | Verify print layout parity |
| `addhours.asp` / `edithours.asp` / `entertime.asp` / `viewhours.asp` / `viewhours_t2c.asp` / `printhours.asp` | Time tracking CRUD + print | K+ | |
| `addexpense.asp` / `enterExpense.asp` / `displayexpense.asp` / `viewexpense.asp` / `printexpense.asp` | Expense tracking CRUD + print | K+ | |
| `addmiles.asp` / `entermiles.asp` / `displaymiles.asp` / `viewmiles.asp` / `printmiles.asp` | Mile tracking CRUD + print | K+ | |
| `deleteEmployee.asp` / `updateEmployee.asp` | Employee management | K+ | |
| `contracts.asp` | Contract viewing | K+ | |
| `jobdescriptions.asp` | Job description reference | K+ | |
| `error.asp` | Custom error page | K+ | |
| `database.asp` | **Server-side include**: connection + helper functions (`validateInput`, `ReadFormVariables`, etc.) | K+ | §6.1: add `connvars.asp` include, remove hardcoded conn |
| `global.asa` | Application lifecycle; `session_onEnd` handler | K+ | §6.15: fix `endsession.asp` reference |
| `styles.css` | Main stylesheet | K | |
| `Web.config` | IIS/ASP.NET config | K+ | §6.2: strip machineKey, debug, Windows auth, Detailed errors |
| `leadlog/` (12 files) | Lead log sub-app (contacts, companies, logs) | K+ | Has own `database.asp` (§6.16) |
| `expense/` (6 files) | Expense sub-app (alternate views) | K+ | |
| `css/` (12 files) | Stylesheets (admin, design, global, layout, login, nav) | K | |
| `images/` (~40 files) | Nav buttons, logos, backgrounds, lightwindow assets | K | |
| `includes/` (8 files) | JS includes (Calendar, lightwindow, date-format) + HTML partials | K | |
| `dropdown/` (3 files) | Dropdown nav (p7exp.js/css, nav.html) | K | |
| `calendar/` (2 files) | Calendar JS + example | K | |
| `announcements/` (8 files) | Announcement images (party, wedding) | K | |
| `scripts/` (selective) | jQuery, jQuery UI (css/js only), jscalendar, timepicker, tablesorter | K | Excludes development-bundle |

## Behaviors that must survive (acceptance matrix)

1. **All read pages** render data from Azure SQL with the same layout and column order as the legacy site.
2. **All mutation pages** (add/update/delete records) succeed and reflect on subsequent reads.
3. **Print pages** produce identical output (line order, markers, page breaks) — capture before/after screenshots for diff verification.
4. **Mode/context switches** route to the correct data tables or stored procedures.
5. **Mutation round-trips**: each add/update/delete followed by its corresponding read page shows the change.
6. **Red/green change display** (if applicable): rows highlight when values differ from prior period.
7. **Copyright footers and date displays** continue to render (date source changes only in Phase 2).

## Defect catalog (do not reproduce; fix schedule)

| # | Defect | Phase | Fix |
|---|---|---|---|
| 1 | Anonymous access to a site that writes the DB | **1** | Forms auth gate (`stafflogin.asp` + `database.asp` session check) is the sole perimeter; platform auth set to Allow Anonymous (no AAD app registration) (§10) |
| 2 | Hardcoded server + password in connection include; leaked `machineKey` in `web.config` | **1** | §6.1 generated `connvars.asp` from pipeline secrets; §6.2 strip machineKey; new login, new password |
| 3 | Dead / stale database connections (legacy server IPs) | **1** | §6.1 shared include pointing to Azure SQL |
| 4 | Junk deployed: test pages, abuse text files, IIS search webbot, `aspnet_client`, `Thumbs.db` | **1** | §5 archive/strip |
| 5 | SQL injection in data pages (string concatenation; weak validation) | **2** | Parameterize all queries through `ADODB.Command`; the §7 least-privilege login bounds damage until done |
| 6 | District/context from cookie set on one page only → implicit fallback in other pages | **2** | Pass context in query string + validate server-side against lookup table |
| 7 | Unvalidated form fields bound directly to recordset writes | **2** | Hidden key per row, validated numeric inputs |
| 8 | Stored procedure double-execution with no lock (concurrent operators can interleave rebuilds) | **2** | Wrap `EXEC` calls in `sp_getapplock`; document single-operator assumption until then |
| 9 | Reports scan the whole table regardless of selected district/context | **2** | Add context filter matching user expectation |
| 10 | Hardcoded "as of" dates + hand-edited dates on specific lines | **2** | Render from `Delivery.deliveryDate` / `ImportJob.CompletedUtc` — deletes a manual Kudu file edit from ops procedure |
| 11 | Dead code: unused session variables, unused FSO objects, overwritten variables, debug SQL echo | **2** | Remove; strip debug output |
| 12 | Stale links: broken navigation targets, hardcoded legacy URLs | **2** | Fix targets; relative URLs |
| 13 | `conn` / recordsets never closed (per-request ODBC handle churn) | **2** | `rs.Close` / `conn.Close` in each page's tail (or a shared `endpage.asp` include) |
| 14 | Latent: any future file-upload feature on this classic site landing in `wwwroot`/`Path.GetTempPath()` | **if added** | §6.5: post to ASP.NET endpoint calling `BlobClient.UploadAsync`, or VBScript `MSXML2.ServerXMLHTTP` PUT to per-request `cw` SAS |
| 15 | `global.asa` `session_onEnd` calls `System.Web.Response.Redirect "endsession.asp"` — file does not exist in the deploy set; uses ASP.NET API in a Classic ASP context | **1** | Replace with `Response.Redirect "logout.asp"` (existing page) or remove the handler if session cleanup is handled elsewhere |
| 16 | `leadlog/database.asp` has its own hardcoded connection (separate from root `database.asp`) | **1** | Apply same `connvars.asp` include pattern (§6.1) to `leadlog/database.asp` |
| 17 | `Web.config` has `<authentication mode="Windows"/>` — conflicts with App Service Entra ID auth; may cause 401 loops for Classic ASP pages | **1** | Remove or set to `None` (§6.2) |
| 18 | `Web.config` has `<httpErrors errorMode="Detailed"/>` — exposes full stack traces to users | **1** | Change to `Custom` (§6.2) |
| 19 | `Web.config` has `<compilation debug="true">` — performance hit + verbose errors in production | **1** | Set to `false` (§6.2) |

## Identity and authentication

### 10.1 Platform-level: App Service Authentication (Entra ID)

- **App Service Authentication** on `intranet-web`: Entra ID tenant app registration, **"Allow unauthenticated requests" OFF**, sign-in action **Login**. Operators sign in with their work/school account; restrict eligible group to the intranet-ops group.
- Classic ASP sees the authenticated user in `Request.ServerVariables("REMOTE_USER")`; no page changes needed in Phase 1 (no page renders the user name).
- HTTPS-only enforced at the App Service level; the custom-domain managed certificate covers the intranet domain and `*.syntaxcom.com`.
- No client certificates, no Windows auth (the browser doesn't present domain creds to App Service Authentication the way old IIS did).

### 10.2 Application-level: Forms authentication (existing site login)

The site has its **own** login flow independent of platform auth:

| Page | Role |
|---|---|
| `stafflogin.asp` | Login form (employee ID + password) |
| `checklogin.asp` | Validates credentials against DB, sets `Session("accesslevel")` = `"A"` or `"E"`, sets `Session("employeeid")` |
| `checkfirstlogin.asp` | First-login forced password change |
| `database.asp` | Gates every page: if `Session("accesslevel")` is not `"A"` or `"E"`, redirects to `Default.asp` |
| `logout.asp` | Clears session, redirects to `stafflogin.asp` |

**Phase 1 (lift & shift): single-layer forms auth.**

```
Browser → stafflogin.asp (forms login) → app
```

- **Decision 2026-10-28:** No AAD app registration is created. App Service Authentication is set to **Allow Anonymous** (disabled). The classic ASP forms login (`stafflogin.asp` → `checklogin.asp` → `Session("accesslevel")`) is the **sole authentication gate**.
- No page changes needed: `checklogin.asp` still validates against the DB, `database.asp` still gates on session vars.
- The `Web.config` `<authentication mode="Windows"/>` is removed (§6.2) — it is an ASP.NET setting irrelevant to Classic ASP.
- Entra ID SSO (replacing forms login with `REMOTE_USER`) remains a **Phase 2 optional** consolidation.

**Phase 2 (consolidation, optional):**

- Replace `stafflogin.asp` / `checklogin.asp` with a single sign-on page that reads `REMOTE_USER` from Entra ID, looks up the employee record by UPN/email, and sets `Session("accesslevel")` + `Session("employeeid")` without a second password prompt.
- Remove the employee password column from the DB (or mark it deprecated).
- `database.asp` gate unchanged (still checks session vars).
- Record the decision in `CONVERSION.md`.

### 10.3 Database authentication

- The site's **database** login is the fixed `syntaxintranet` SQL user for every user — same as today's shared credential. Per-user DB accounts are out of scope; audit is supplied by SQL Audit + App Insights instead.

## Environment and configuration

| Setting | Value |
|---|---|
| App name / plan | `intranet-web` on **`postal-web-plan`** (Windows, RG `Syntax`) |
| Runtime stack | .NET 4.8 (Windows) |
| Platform bits / pipeline | **32 Bit / Classic** |
| Default document | `index.asp` (via `<defaultDocument>` in `Web.config`, §6.2) |
| Always On | **true** (keeps app warm, prevents cold starts) |
| SCM type | **None** (Basic Auth Publishing Credentials = false) |
| App Service Authentication | **Disabled** (Allow Anonymous); forms auth in ASP code is the sole gate. No AAD app registration. |
| App settings | **none required for the site** (connection string deliberately *not* an app setting — classic ASP can't read it; see §6.1). `APPINSIGHTS_INSTRUMENTATIONKEY` via standard integration. `SCM_DO_BUILD_DURING_DEPLOYMENT=false`. |
| Secrets (CI/CD variable group, pipeline-only) | `INTRANET_DB_SERVER=syntax-sql.database.windows.net`, `INTRANET_DB_NAME=SyntaxIntranet`, `INTRANET_DB_USER=syntaxintranet`, `INTRANET_DB_PASSWORD=fresh, Key Vault-backed` |
| SQL firewall | Allow Azure Services (+ the legacy VM IP range only during cutover) |
| Monitoring | App Insights; alert 5xx > 5 in 5 min; SQL Audit on |

## Cutover plan

1. **Stage first**: deploy to a `intranet-staging-…azurewebsites.net` (or second slot) instance pointed at a **copy** of the database. Run the full acceptance matrix (§9) against real data.
2. **Import side**: `spec.md`'s importer runs against the same Azure SQL; do one real import through the new pipeline **before** cutting the site, so the site's first live read on Azure is post-import.
3. **Cut DNS**: custom domain CNAME → `intranet-web`. Keep the legacy server warm for **two full cycles**.
4. **Rollback**: repoint CNAME back to the legacy server; no data migration exists in the reverse direction except context tables — sync rule during the warm window: legacy server is read-only; all edits go to Azure.
5. **Decommission** legacy server after two clean cycles; update operator runbooks (drop FTP/Remote-Desktop steps; automation replaces manual edits).

## Acceptance criteria

- **Page parity**: every §9 behavior reproduced; for print pages, capture before/after print preview screenshots of the same data and diff-verify line order, markers, page breaks.
- **Mode/context switch**: after toggle, read pages pull the correct table/data; stored procedures executed (SQL Profiler/Query Store shows both `EXEC`s); appropriate wait message present.
- **Mutation round-trips**: add/duplicate/delete a throwaway record + context entries; each reflects on its read page; row counts reconcile.
- **Security**: unauthenticated request → Entra sign-in (not a 200); `curl` from a non-allowlisted network → HTTPS redirect; parameter probe (`district' OR 1=1--`) on every input returns validation error/empty, not a stack trace (Phase 1: bounded by least-priv login; Phase 2: parameterized).
- **Injection regression tests** (Phase 2): one automated pass per page against the defect catalog.
- **Observability**: an induced 500 appears in App Insights with request ID; no credentials in the deployed zip (scan artifact).
- **Upload path (only if §6.5 is enabled)**: a test upload lands in the `syntaxstoragecontainer1` container with the correct name/size, the page stores the blob URL (SAS nowhere in DB or logs), and nothing was written to `wwwroot`/temp.

## `CONVERSION.md` entry points (record as facts)

- Chose lift & shift over .NET rewrite — reasons; hosting matrix confirming Classic ASP + ADODB on Windows App Service.
- Resource group: **Syntax**.
- App Service name: **`intranet-web`**.
- Source path: `D:\Webs\Syntax\syntaxintranet\trunk`.
- Migration output: `D:\Webs\Syntax\syntaxintranet\migration`.
- Connection string travels via generated `connvars.asp` (not an app setting — classic ASP limitation).
- Authentication: App Service Authentication + Entra ID; no anonymous access.
- SQL login: new least-privilege `syntaxintranet` user (separate from importer identity).
- App Service Plan: **`postal-web-plan`** (existing Windows plan, RG `Syntax`).
- Database: **`SyntaxIntranet`** on server **`syntax-sql`** (RG `Syntax`).
- Phase 1 = deploy, fix connections, strip junk, add auth. Phase 2 = parameterize queries, fix stale links, remove dead code, automate date rendering.

## Status

| Item | Status | Notes |
|---|---|---|
| Source inventory complete | ✅ Done | 62 ASP files + 9 dirs cataloged; `deploy-list.txt` created |
| Page inventory table filled | ✅ Done | §8 populated with all pages and dispositions |
| Defect catalog verified against source | ✅ Done | 19 defects identified from actual source review |
| Files copied to migration folder | ✅ Done | `D:\Webs\Syntax\syntaxintranet\migration\web\` populated |
| Deploy script created | ✅ Done | `infra/web/deploy-website-local.ps1` + `gen-connvars.ps1` |
| SQL grants drafted | ☐ Pending | Replace template in §7 with actual table/procedure names from `SyntaxIntranet` DB |
| `connvars.asp` generation pipeline defined | ☐ Pending | CI/CD step to pull secrets from Key Vault and write include file |
| `database.asp` + `leadlog/database.asp` edited | ☐ Pending | Add `connvars.asp` include, remove hardcoded ODBC connection |
| `Web.config` cleaned | ☐ Pending | Strip machineKey, debug, Windows auth, Detailed errors |
| `global.asa` fixed | ☐ Pending | Replace `endsession.asp` reference with `logout.asp` |
| App Service `intranet-web` provisioned | ☐ Pending | Deploy to `postal-web-plan` (RG `Syntax`) |
| Staging deployment successful | ☐ Pending | Acceptance matrix passed against copy of database |
| DNS cutover complete | ☐ Pending | Custom domain pointed to `intranet-web` |
| Legacy server decommissioned | ☐ Pending | After two clean cycles |

---

*Created by Postal Migrator agent — 2026-10-27. Model: GitHub Copilot (cfettinger / GitHub Copilot). This spec is independent of the Postal migration; it targets the Syntax Intranet Classic ASP site.*
