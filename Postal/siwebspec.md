# Spec: Classic ASP Syntax Intranet website (`trunk` → Azure App Service Windows, lift & shift)

Version 1.0, 2026-10-27

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

- **App Service `intranet-web`** — Windows, .NET 4.8 runtime stack (stack is irrelevant beyond "Windows"; pick .NET 4.8), Basic B1+ (may share the importer's Windows plan if the importer runs there; otherwise its own plan — two apps never share code). Configuration:
  - **Platform: 32 Bit; Managed pipeline: Classic**; HTTPS-only enabled; Application health monitoring on; Pre-/post-compilation handlers unused.
  - **Authentication: Entra ID (App Service Authentication)**, "Allow unauthenticated users = No" (§10).
  - Custom domain (CNAME) with App Service-managed certificate.
- **New SQL login `syntaxintranet`** in the shared database (§7). The importer's identity from `spec.md` is unchanged.
- **App Insights** — reuse; the site's failures (500s, ADODB errors) land in the same component or a second one. Alert on 5xx spikes.
- Storage account: **none in Phase 1**. No queue, no Function. If the §6.5 upload add-on is enabled, reuse `syntaxstoragev2` (container `syntaxstoragecontainer1`) — do not create a second one.

## Source inventory and cleanup

Working copy: `trunk/`. Deploy set = column 2 only.

**Deploy (as-is):** All production `.asp` pages, `styles.css`, `nav.html`, all `*.gif` nav/header images, `web.config` (edited per §6.2), and any supporting assets referenced by the live pages.

**Move to `/_archive/` (do not deploy; keep in repo for reference):**
- Test/experiment `.asp` files not used by production navigation.
- Any stale email-test or debug pages.
- Junk files (e.g., single-line abuse text, scratch pages).

**Do not deploy at all:** `backup/` (stale revisions), `aspnet_client/` (auto-generated .NET runtime), `Thumbs.db`, IIS search webbot pages, solution files (`.sln`), IDE folders (`.vs/`).

## Phase 1 code changes (small, mechanical)

### 6.1 Database connection — `database.asp` (or equivalent include)

Today (per request, every page):
```asp
<!--#include file="connvars.asp"-->
conn.Open ConnString, DbUser, DbPassword
```
(Commented lines above it show the address history and legacy credentials.)

Change to:
```asp
<!--#include file="connvars.asp"-->' connvars.asp generated by CI/CD from Key Vault secrets
' ...
conn.Open ConnString, DbUser, DbPassw
```

`connvars.asp` is **generated at deploy time** by the CI/CD pipeline from Key Vault secrets — never committed to source. The include path stays the same; only its content changes.

### 6.2 `web.config` cleanup

Strip:
- `<machineKey>` (leaked / hardcoded).
- Any inline connection strings or credentials.
- Legacy IIS handler mappings not needed by Classic ASP.

Keep:
- `<customErrors mode="RemoteOnly" />` (or `On` in production to hide stack traces).
- `<httpErrors errorMode="Custom" />` with a friendly 500 page.
- Static content and directory browsing settings as needed.

### 6.3 App Service configuration

Set these application settings on `intranet-web`:

| Setting | Value |
|---|---|
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Auto-injected by App Insights integration (or set manually). |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `false` (no build step for Classic ASP). |

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
CREATE USER [SyntaxIntranet] FOR LOGIN [syntaxintranet];
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
| ASP session variables (e.g., `session("mode")`) | In-process session | Pages that branch on mode/district | **Keep `intranet-web` at 1 instance in Phase 1** (in-process session is fine). If scale-out is ever needed: move mode into the selection page's query string, or configure SQL/Redis session state. |
| Cookie-based state | Browser cookie | Pages that read district/context from cookies | Known defect: cookie usually unset → fallback to default. Phase 1 keeps behavior; Phase 2 switches all context to query string/validated session value. |
| Client-side nav state | JS in every page | nav highlights (`MM_swapImage`) | Keep as-is. |

## Page inventory (role verified against source)

Disposition: **K** = deploy unchanged, **K+** = deploy with the §6 edits only, **A** = archive.

| Page | Role (verified) | Disp. | Notes / drift warnings |
|---|---|---|---|
| *(Populate from actual source inventory)* | *(Description)* | K/K+/A | *(Drift notes)* |

> **Action required:** Walk the `trunk/` directory, catalog every `.asp` file, verify which are reachable from navigation, and fill this table before implementation.

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
| 1 | Anonymous access to a site that writes the DB | **1** | App Service Authentication, Entra ID, no anonymous (§10) |
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

## Identity and authentication

- **App Service Authentication** on `intranet-web`: Entra ID tenant app registration, **"Allow unauthenticated requests" OFF**, sign-in action **Login**. Operators sign in with their work/school account; restrict eligible group to the intranet-ops group.
- Classic ASP sees the authenticated user in `Request.ServerVariables("REMOTE_USER")`; no page changes needed in Phase 1 (no page renders the user name).
- HTTPS-only enforced at the App Service level; the custom-domain managed certificate covers the intranet domain and `*.syntaxcom.com`.
- No client certificates, no Windows auth (the browser doesn't present domain creds to App Service Authentication the way old IIS did).
- The site's **database** login is the fixed `SyntaxIntranet` SQL user for every user — same as today's shared credential. Per-user DB accounts are out of scope; audit is supplied by SQL Audit + App Insights instead.

## Environment and configuration

| Setting | Value |
|---|---|
| App name / plan | `intranet-web`, Windows, B1+ (shared plan with the importer allowed if it runs Windows) |
| Runtime stack | .NET 4.8 (Windows) |
| Platform bits / pipeline | **32 Bit / Classic** |
| Default document | `index.asp` |
| App Service Authentication | Entra ID, anonymous off |
| App settings | **none required for the site** (connection string deliberately *not* an app setting — classic ASP can't read it; see §6.1). `APPINSIGHTS_INSTRUMENTATIONKEY` via standard integration. |
| Secrets (CI/CD variable group, pipeline-only) | `INTRANET_DB_SERVER`, `INTRANET_DB_NAME`, `INTRANET_DB_USER=new login syntaxtntranet`, `INTRANET_DB_PASSWORD=fresh, Key Vault-backed` |
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
- Phase 1 = deploy, fix connections, strip junk, add auth. Phase 2 = parameterize queries, fix stale links, remove dead code, automate date rendering.

## Status

| Item | Status | Notes |
|---|---|---|
| Source inventory complete | ☐ Pending | Walk `trunk/`, catalog `.asp` files, verify navigation reachability |
| Page inventory table filled | ☐ Pending | Populate §8 with actual pages and dispositions |
| Defect catalog verified against source | ☐ Pending | Confirm each defect exists in the working copy |
| SQL grants drafted | ☐ Pending | Replace template in §7 with actual table/procedure names |
| `connvars.asp` generation pipeline defined | ☐ Pending | CI/CD step to pull secrets from Key Vault and write include file |
| App Service `intranet-web` provisioned | ☐ Pending | Bicep/azd template update |
| Staging deployment successful | ☐ Pending | Acceptance matrix passed against copy of database |
| DNS cutover complete | ☐ Pending | Custom domain pointed to `intranet-web` |
| Legacy server decommissioned | ☐ Pending | After two clean cycles |

---

*Created by Postal Migrator agent — 2026-10-27. Model: GitHub Copilot (cfettinger / GitHub Copilot). This spec is independent of the Postal migration; it targets the Syntax Intranet Classic ASP site.*
