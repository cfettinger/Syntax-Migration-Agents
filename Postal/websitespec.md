# Spec: Classic ASP postal website (SVN `website/postal.svn` → `trunk/website/web`) → Azure App Service (Windows, lift & shift)

Version 1.1, 2026-10-13 (v1.1: added §6.5 file-upload-to-blob path mirroring the `syntax-webapp.txt` upload Q&A; adjusted non-goals and resource delta)

Companion to `spec.md` (desktop importer → .NET 10). This spec covers the operator-facing website at `trunk/website/web` (**Classic ASP / VBScript / ADODB** on IIS, circa 2010–2014).

> **Source note:** the upstream SVN repo is `website/postal.svn`; only the working copy `trunk/website` is available locally (`Postal.sln`, `.vs/`, `web/`). Export the working copy fresh at implementation time so no local edits are lost. The repo itself moves to the new source-control layout in §12 (or stays SVN with a scripted export step — decide and record in `CONVERSION.md`).

## Goal

Move the existing ASP website to Azure **with a lift & shift, not a rewrite**: host the VBScript pages as-is in a Windows App Service, fix the connection layer, strip dead/junk files, add authentication, and point everything at the same Azure SQL database specified in `spec.md`.

1. A Windows App Service (`postal-web`) serves the site at `postal.syntaxcom.com` (custom domain, HTTPS-only).
2. All pages keep their current URLs, form names, and printed output byte-for-byte in intent (see §9, "Behaviors that must survive").
3. Database access goes to the shared **Azure SQL** database via a new least-privilege SQL login; no credentials in source.
4. Phase 2 (after cutover) retires the legacy VM/SQL without changing what operators see.

This follows the hosting findings in `syntax-webapp.txt`: **Classic ASP + VBScript + ADODB runs on Azure App Service (Windows)** out of the box — ADODB is a built-in Windows COM component, no DLL registration needed, which is exactly what this site requires (no custom COM; `crlf.exe`-style desktop bits are out of scope here).

## Non-goals

- **No rewrite to .NET 10 / C# / MVC.** `spec.md` rewrites only the desktop importer. Converting the site's ~30 ASP pages to Razor is a later, optional project; this spec deliberately keeps them in VBScript. (Record the decision and the reason — minimal-diff cutover of a working, rarely-changing site — in `CONVERSION.md`.) If any piece *were* rewritten in .NET, its uploads must stream `IFormFile` → `BlobClient.UploadAsync` — never `CopyToAsync` to a local path (see `syntax-webapp.txt` rewrite-upload Q&A and §6.5).
- No changes to printed/facing-slip layouts, page-break behavior, or report wording.
- No redesign of the image-button nav (Dreamweaver `MM_swapImage` gifs stay).
- Do not modify the black-box stored procedures `Postalweb` / `Postalwebboth` (owned by `spec.md`'s database migration).
- Do not port `test.asp`-style experiments, the IIS text-search page, or `backup/` into production.
- No file uploads **in Phase 1**: this site only reads/writes the database, so it needs no queue and no worker. If an upload feature is ever added to the classic site (e.g. an operator POSTing `delstat.txt` from the site instead of FTP), follow §6.5 — files never land on `wwwroot` or `Path.GetTempPath()`, and the storage account reused is the one `spec.md` already provisions.

## Hosting decision

| Option | Verdict | Reason |
|---|---|---|
| **A. Windows App Service, site deployed as-is to `wwwroot`** | **Chosen** | `syntax-webapp.txt` confirms the stack is supported; lowest risk; zero code logic changes beyond §6; ADODB/SQLOLEDB built in. |
| B. Windows container with IIS | Rejected | Only needed for custom COM registration; none exist here. |
| C. Windows VM re-hosted IIS | Rejected | Defeats the migration; keep only as rollback during cutover (it already exists — the legacy server `69.20.14.96`). |
| D. Rewrite to .NET 8 MVC | Deferred | High effort, high regression risk on 20+ page-flows incl. print formatting; do it only if the site later needs scale-out, auth-by-role, or CI test coverage. |

One note from `syntax-webapp.txt` that does **not** apply: "use Connection strings app settings for the database". Classic ASP **cannot read App Service connection-string settings** (they surface to IIS/.NET only). The connection string therefore travels via a generated include file (§6.1). Everything else in that guidance applies: Windows (not Linux) plan, **32-bit platform**, **Classic managed pipeline**, Basic B1 or higher, firewall "Allow Azure services", SQLOLEDB provider string.

## Azure resources (delta vs `spec.md`)

`spec.md` already provisions App Service (importer), Storage, Azure SQL, managed identity, Key Vault, App Insights. This spec **adds one resource and one service principal/login**:

> **Azure AI Services / Foundry note (future work):** Subscription `5a5056f9-2199-4063-9133-0d9a32714a8a` is eligible to upgrade from **AI Services Free Tier** to **Tier 1**. This is informational and does not change the classic ASP website lift-and-shift plan, but it enables optional future **Azure AI Foundry Agent** additions (operator help/automation) under the same subscription.

- **App Service `postal-web`** — Windows, .NET 4.8 runtime stack (stack is irrelevant beyond "Windows"; pick .NET 4.8), Basic B1+ (may share the importer's Windows plan if the importer runs there; otherwise its own plan — two apps never share code). Configuration:
  - **Platform: 32 Bit; Managed pipeline: Classic**; HTTPS-only enabled; Application health monitoring on; Pre-/post-compilation handlers unused.
  - **Authentication: Entra ID (App Service Authentication)**, "Allow unauthenticated users = No" (§10).
  - Custom domain `postal.syntaxcom.com` (CNAME) with App Service-managed certificate.
- **New SQL login `postalweb`** in the shared database (§7). The importer's identity from `spec.md` is unchanged.
- **App Insights** — reuse; the site's failures (500s, ADODB errors) land in the same component or a second one. Alert on 5xx spikes.
- Storage account: **none in Phase 1**. No queue, no Function. If the §6.5 upload add-on is enabled, reuse `spec.md`'s storage account (container `syntaxstoragecontainer1`) — do not create a second one.

## Source inventory and cleanup

Working copy: `trunk/website/web/`. Deploy set = column 2 only.

**Deploy (as-is):** `database.asp`, `index.asp`, `changemode.asp`, `mode.asp`, `setsession.asp`, `deliverystat.asp`, `postaldata.asp`, `deliveryenter.asp`, `postalss.asp`, `SpreadSheetHTML.asp`, `printdata.asp`, `FacingSlips.asp`, `facingslipsHTML.asp`, `facingslipspinebush.asp`, `facingslipsroselle.asp`, `labels.asp`, `updatelabels.asp`, `addlabel.asp`, `deletelabel.asp`, `savelabels.asp`, `FlagReport.asp`, `officecopies.asp`, `updateoffice.asp`, `NewDistrict.asp`, `newroute.asp`, `addnewroute.asp`, `saveroute.asp`, `deleteroute.asp`, `deletechoose.asp`, `updatedelete.asp`, `commentsupdate.asp`, `styles.css`, `postal.txt`, `nav.html`, all `*.gif` nav/header images, `web.config` (edited per §6.2).

**Move to `/_archive/` (do not deploy; keep in repo for reference):**
- `routeupdate.asp` — a CDO "test email to localhost SMTP" experiment page, not the route-update page (that is `updatedelete.asp`);
- `test2.asp` — `year(date)` scratch page.
- `a.asp` — one line of abuse text; `a.html.txt` — same family of junk.

**Do not deploy at all:** `backup/` (33 stale revisions — useful only for disambiguating drift, §8), `aspnet_client/` (auto-generated .NET 1.1 runtime), `Thumbs.db`, `search.htm` (Visual InterDev `webbot bot='Search'` page posting to `_vti_script/search.htm0.idq` — IIS 4-era text search, no equivalent), `Postal.sln`, `.vs/`.

**Note on `postal.txt`:** despite the extension it is CSS, linked via `<link href="postal.txt">`. Keep the file and the link; optionally rename to `postal.css` and update the ~20 `<link>` tags in one find/replace (record choice in `CONVERSION.md`).

## Phase 1 code changes (small, mechanical)

### 6.1 Database connection — `database.asp`

Today (per request, every page):
```asp
<!-- Use a protected include or secret manager instead of inline credentials -->
<!--#include file="connvars.asp" -->
conn.Open ConnString, DbUser, DbPassword  <!-- ConnString and DbUser/DbPassword are defined in connvars.asp or loaded from a secret store -->
```
(Commented lines above it show the address history: `76.12.176.180/syntaxcms`, `208.112.84.42`, `192.168.1.124`, `REDACTED_LEGACY_USER sa`.)

Change to:
```asp
<!--#include file="connvars.asp"-->
' ...
conn.Open ConnString, DbUser, DbPassword
```
- `connvars.asp` defines `ConnString`, `DbUser`, `DbPassword`. Provider: **`SQLOLEDB`** (always present on Windows; removes the dependency on "ODBC Driver 17 for SQL Server" being in the App Service image):
  `Provider=SQLOLEDB;Data Source=tcp:<server>.database.windows.net,1433;Initial Catalog=postal;`
- `connvars.asp` is **git-ignored** and generated at deploy time by the CI/CD pipeline (Azure DevOps variable-group secrets injected into the release zip, or written via Kudu by a pre-deploy script). Never committed. The legacy password **must not** be reused as the new password.
- The two standalone-connection pages `facingslipspinebush.asp` / `facingslipsroselle.asp` open their own `sa;Data source=REDACTED_LEGACY_USER` connections (dead since the old server died). Replace lines 2–5 of each with the same `connvars.asp` include and use the shared `conn` — their queries then run against `DelstatWebBoth` in the new database and they behave exactly as before.
- Keep everything else in `database.asp` untouched: `sql_execute` (parameterized ADODB.Command helper — currently **defined but never used**; becomes the Phase 2 tool instead of deleting it), `validateInput`, `validateZip`, `returnValidated`, `returnZipValidated`, and `Sub ReadFormVariables(ByRef message, ByRef error)` (line 34; used by `NewDistrict.asp` and `test.asp`).

### 6.2 `web.config`

Remove the hardcoded `<machineKey>` (SHA1/AES, leaked). No authentication sections needed — auth moves to App Service Authentication (§10). No `.NET` handlers are used by any deployed page, so the config can be minimal; if anything else depends on it, keep defaults and only delete the `machineKey` element. Default document stays `index.asp` (set in IIS/App Service configuration, not the file).

### 6.3 Nothing else in Phase 1

No logic edits, no SQL text edits. Page behavior is byte-identical except: correct database, authenticated access, no junk pages.

### 6.4 One nav fix

`SpreadSheetHTML.asp` links "Update Routes" to `routeupdate.asp`, which is the CDO email experiment (§5). Repoint the link to `updatedelete.asp` at deploy time so the button isn't broken on Azure. (Listed here even though it is a one-attribute edit; it is the only Phase 1 behavioral change.)

### 6.5 File-upload-to-blob path (only if an upload feature is added)

Phase 1 ships without uploads. If the classic site later gains an upload feature (e.g. operator drops `delstat.txt` on a page instead of FTPing + RDPing), mirror the `syntax-webapp.txt` upload Q&A instead of ad-hoc'ing it:

- **Durability rule:** on App Service only the site content path is durable (Windows: `D:\home\site\wwwroot\...`; Linux not applicable here). `Path.GetTempPath()` and anything outside it are wiped on restart or scale-out. **Never treat `wwwroot` as the archive** — it is the site and a poor store. Target is always a blob.
- **Rejected pattern:** ASP writes the file to disk, then a WebJob/timer Function copies it to the container and deletes the local copy. Race-prone, and the file briefly lives on the instance (violates the durability and single-copy invariants).
- **Recommended pattern: post the form to a small ASP.NET endpoint** (in the importer app from `spec.md`, or a minimal endpoint) that receives the `IFormFile`, calls `BlobClient.UploadAsync(stream, overwrite:)`, and **returns the blob URL** for the `.asp` page to store. Handles multipart forms cleanly (multiple fields, non-ASCII names), any file size, and keeps the credential (SAS or managed identity) out of VBScript.
- **Pure-VBScript alternative (one file field only):** PUT the bytes straight to a SAS blob URL from the page, no local disk:
  ```vbscript
  Dim bytes, http
  bytes = Request.BinaryRead(Request.TotalBytes)
  Set http = Server.CreateObject("MSXML2.ServerXMLHTTP.6.0")
  http.Open "PUT", "https://ACCOUNT.blob.core.windows.net/syntaxstoragecontainer1/<name>?<SAS>", False
  http.SetRequestHeader "x-ms-blob-type", "BlockBlob"
  http.SetRequestHeader "Content-Type", "application/octet-stream"
  http.Send bytes
  If http.Status <> 201 Then ... ' fail with http.Status / responseText
  ```
  Known limitations (from `syntax-webapp.txt`): `Request.BinaryRead` returns the **whole** request including the multipart boundary, so a normal form post is not a clean blob — strip the MIME headers (the single-`.asp` strip shown there: `InStr(bin,"filename=""")`, split on `vbCrLf & vbCrLf`/`InStrRev(bin, vbCrLf & "--")`, `BinaryToString`/`StringToBinary` ADODB.Stream helpers) or fall back to the ASP.NET endpoint. The strip **breaks on extra form fields and non-ASCII filenames**. The SAS needs **`cw` (create, write)** and must be short-lived (mint per-request from the importing app's managed identity — it already holds Storage Blob Data Delegator from `spec.md`). Store the **blob URL** in the database, never the SAS.
- **`delstat.txt` itself stays out of scope for this path:** the national file is ~209 MB and the sanctioned import path remains `spec.md`'s browser-direct block upload (user-delegation SAS). This section only covers small auxiliary files if ever needed.

## Data and permissions

Shared Azure SQL database (per `spec.md`). The website touches: `Delstat` (raw read in `postaldata.asp`), `DelstatWeb`, `DelstatWebBoth` (all report pages), `DistrictLookup`, `DistrictInfo`, `DistrictLabels`, `Delivery`, plus `EXEC Postalweb` / `EXEC Postalwebboth` (mode switch, route/district add/delete).

Login `postalweb` (SQL-user, not the importer's identity — isolates the site's write surface):

| Table / object | Grant |
|---|---|
| `Delstat`, `Delivery` | SELECT |
| `DelstatWeb`, `DelstatWebBoth` | SELECT, **UPDATE** (manual `totpos` overrides, `updatedelete.asp`) |
| `DistrictLookup` | SELECT, INSERT, DELETE |
| `DistrictInfo` | SELECT, UPDATE |
| `DistrictLabels` | SELECT, INSERT, UPDATE, DELETE |
| `Postalweb`, `Postalwebboth` | EXECUTE |
| `ImportJob` | none |
| `Delstat` DML, `TRUNCATE`, `db_owner` | **not granted** |

```sql
CREATE USER [postalweb] FOR LOGIN [postalweb];
GRANT SELECT ON dbo.Delstat, dbo.Delivery, dbo.DelstatWeb, dbo.DelstatWebBoth,
       dbo.DistrictLookup, dbo.DistrictInfo, dbo.DistrictLabels TO [postalweb];
GRANT UPDATE ON dbo.DelstatWeb, dbo.DelstatWebBoth, dbo.DistrictInfo TO [postalweb];
GRANT INSERT, UPDATE, DELETE ON dbo.DistrictLabels TO [postalweb];
GRANT INSERT, DELETE ON dbo.DistrictLookup TO [postalweb];
GRANT EXECUTE ON dbo.Postalweb, dbo.Postalwebboth TO [postalweb];
```
This least-privilege set also **contains the blast radius of the site's remaining SQL injection** (§8) if Phase 2 slips: an attacker cannot truncate `Delstat` or write `ImportJob`, and only the enumerated DML surfaces exist.

## State model

Legacy state, all of it:

| State | Where | Used by | Migration |
|---|---|---|---|
| `session("mode")` = `"R"` (residential) / other (both) | ASP session | table choice `delstatweb` vs `delstatwebboth` in `deliveryenter`, `postalss`, `SpreadSheetHTML`, `printdata`, `FacingSlips`, `facingslipsHTML`, `FlagReport` | Stays an ASP session cookie (`.ASPSESSIONID`). **Keep `postal-web` at 1 instance in Phase 1** (in-process session is fine). If scale-out is ever needed: move mode into the selection page's query string, or configure SQL/Redis session state — record in `CONVERSION.md`. |
| `session("code") = "N"` (set in `setsession.asp`) | ASP session | **never read** | Dead. Leave in Phase 1; remove in Phase 2. |
| `Response.Cookies("schooldistrict")` | Cookie | **written** only by `SpreadSheetHTML.asp`; **read** by `deletelabel.asp`, `updatedelete.asp`, `commentsupdate.asp`, `deleteroute.asp` | Known defect: the cookie is usually unset (only set after visiting the spreadsheet page), so those pages fall back to district `"ANY"` and operate on an implicit default. Phase 1 keeps behavior; Phase 2 switches all district context to a query string/validated session value (§8). |
| MM_swapImage client state | JS in every page | nav highlights | Keep as-is. |

## Page inventory (role verified against source)

Disposition: **K** = deploy unchanged, **K+** = deploy with the §6 edits only, **A** = archive.

| Page | Role (verified) | Disp. | Notes / drift warnings |
|---|---|---|---|
| `index.asp` | Home; `frmschool` mode radios res/both → `POST changemode.asp`; "Please allow 90 seconds" | K+ | Quick-links point at hardcoded `http://postal.chasestaging.net/*` — make URLs relative in Phase 2. |
| `changemode.asp` / `mode.asp` | 14-line exec page: `mode="res"` → `EXEC Postalweb` else `EXEC Postalwebboth`; redirect `index.asp` | K+ | The only "mode" mechanism; both files exist across generations — confirm which is the live link target and archive the other. |
| `setsession.asp` | `session("mode")=request("mode")`; validates district; redirect `postaldata.asp?schooldistrict=` | K+ | Sets dead `session("code")`. |
| `deliverystat.asp` | ZIP-entry form (JS-validated) posting to itself; **line ~59 holds the manually edited "last updated" date** (ops Step 6) | K+ | Phase 2: read the date from `Delivery.deliveryDate` (or `ImportJob.CompletedUtc`) instead of hand-editing the file on Kudu after every import. |
| `postaldata.asp` | ZIP report: `SELECT updatekey,routeid,SUM(posr*/posb*/actr*/actb*) FROM delstat WHERE zipcode='…'` + `Delivery.deliveryDate`; "COPYRIGHT(C) month-02 USPS"; hardcoded "Monthly Routes as of 4/15/2014" | K+ | Reads **raw `Delstat`**, not the web tables. Phase 2: pull the as-of date from the DB; parameterize ZIP. |
| `deliveryenter.asp` | Main district view of `delstatweb[both]` (Current/Last month/Change, row turns red on change); links `postalss.asp`, `facingslips.asp`; district `<select>` → `postaldata.asp?schooldistrict=` | K+ | The `postaldata.asp?schooldistrict=` target is stale — current `postaldata.asp` wants `zipcode`. Fix the link in Phase 2 (or restore the district overload). |
| `postalss.asp` | "View Spreadsheet": per-postoffice route lines + SubTotal; `routeid` starting `B` rolled into a "Boxes" line; labels, Pieces Mailed/Labeled, Total Mailed, Office Copies, Total Print | K+ | |
| `SpreadSheetHTML.asp` | Nav'd district page: print links (`printdata`, `facingslipsHTML`, self), **Update Routes → `routeupdate.asp` (dead — the page is a CDO test)**, comments + `commentsupdate.asp`; sets the `schooldistrict` cookie | K+ | §6.4: repoint the link to `updatedelete.asp` at deploy. |
| `printdata.asp` | Print-format data page (postoffice/zip/route/amount, Boxes, SubTotal, labels, office copies, Total Print) | K+ | |
| `FacingSlips.asp` | Plain-HTML slips: `routeid not like 'B%'` → slip (postoffice, zip zero-padded to 5 if 4-digit, `ROUTE#`, totpos "PIECES", `****ECRWSS****`); then Boxes slips aggregating `like 'B%'` | K+ | District `PINE BUSH` → `Response.Redirect "facingslipspinebush.asp"` (line 24). |
| `facingslipsHTML.asp` | Printable slips: 900px tables, `page-break-after:always`, `window.print()`; validates district against `DelstatWebBoth` | K+ | |
| `facingslipspinebush.asp` | District variant: **query is hardcoded `schooldistrict='WESTBURY'`** (name/district mismatch — legacy, known); slips chunked **100 pieces**; standalone `sa;REDACTED_LEGACY_USER` connection | K+ | §6.1 connection fix; keep the WESTBURY query as-is; document the name/district mismatch in `CONVERSION.md`. |
| `facingslipsroselle.asp` | District variant: hardcoded `'deerpark'`; slips chunked **50 pieces**; standalone `sa` connection; **no page links to it** (direct URL only) | K+ | §6.1 fix; keep (operators bookmark it) or confirm retirement with the operator before cutting. |
| `labels.asp` → `updatelabels.asp` → `addlabel` / `deletelabel` / update-form → `savelabels.asp` | Label location count maintenance on `DistrictLabels` | K+ | `savelabels.asp` is all three mutations by hidden `code` (1 add / 2 delete / positional updates). `deletelabel.asp` reads the **cookie** (defect). |
| `NewDistrict.asp` | Add school district: `mode="2"` → `ReadFormVariables`, zip validation, `INSERT DistrictLookup`, `EXEC Postalwebboth` (only), success page | K+ | Only rebuilds `postalwebboth`, not `postalweb` — asymmetry vs other pages; preserve as-is, note in `CONVERSION.md`. |
| `newroute.asp` → `addnewroute.asp` | Add route: `CommandTimeout=300`; `INSERT DistrictLookup`; then `EXEC postalwebboth` **and** `EXEC Postalweb`; "Please allow two minutes" | K+ | |
| `saveroute.asp` | Full route-add form (postoffice dropdown from distinct per district **or** alt text, zipcode, routeid ≤5 with C=carrier / R=rural / `BOXE…`=boxes); form `action="saveroute.asp"` posts to **itself** while the insert lives in `addnewroute.asp` | K+ | Role drift: verify against `backup/` which page the nav button really drives; wire the live path (nav → `newroute.asp` → `addnewroute.asp` handler) and archive whichever is orphaned after verification. |
| `deleteroute.asp` → `deletechoose.asp` | Delete routes: form lists `DistrictLookup` per district (checkbox `chooseroute` values encode `routeid + zipcode + postoffice`, `BOXE…` routes 5 chars wide) → handler deletes each, then `EXEC postalwebboth` + `EXEC Postalweb` | K+ | Handler parses with `mid()`: normal `routeid=mid(1,4), zip=mid(5,5), po=mid(10,…)`; `BOXE*` `routeid=mid(1,5), zip=mid(6,5), po=mid(11,…)`. |
| `updatedelete.asp` | "Update Routes": per-row inputs `name=routeid+zipcode+postoffice`, `mode="2"` → `UPDATE delstatweb[both] SET totpos=<value>` (raw, non-parameterized, echoes the SQL to the page), redirect `postalss.asp`; district from **cookie** | K+ | **Manual `totpos` overrides are volatile**: the next `Postalweb`/`Postalwebboth` run (next import!) overwrites them. Preserve behavior; Phase 2 option: persist overrides in a table the SPs honor — coordinate with the SP owner. |
| `commentsupdate.asp` | District comments editor on `DistrictInfo.comments`; district from **cookie**; minimal `'`→`''` escaping | K+ | |
| `FlagReport.asp` | Flag threshold radios 10/20/30/40; scans **whole** `delstatweb[both]` (no district filter); rows where |Current−Last| ≥ threshold, green/red | K+ | |
| `officecopies.asp` → `updateoffice.asp` | `DistrictInfo.officecopies` upsert (`IsNumeric` or literal `"1"`) | K+ | |
| `postal.txt` | CSS (misnamed) | K | |
| `nav.html`, `styles.css`, `*.gif` | Image-button nav + styles | K | |

## Behaviors that must survive (acceptance anchors)

1. **Mode switch** `res` → `POST changemode.asp` → `EXEC Postalweb` (or `Postalwebboth`) → all reports flip between `delstatweb`/`delstatwebboth` on the next request; user waits ~90 s.
2. **Print output**: `window.print()` triggers; `page-break-after:always` per slip; 900px slip tables; font sizes 8/12; `****ECRWSS****` centered marker; zip codes zero-padded to 5 digits when stored as 4.
3. **Boxes aggregation**: any `routeid` starting `B` (`'BOXES'`) sums into per-postoffice "Boxes" lines/slips in `postalss`, `printdata`, `FacingSlips`, `facingslipsHTML`; district variants chunk at Pinebush/Westbury=100 per slip, Roselle/Deerpark=50.
4. **District special case**: selecting `PINE BUSH` on the slip page redirects to `facingslipspinebush.asp`.
5. **Mutation round-trips** (each followed by the two SP rebuilds where the legacy page does them): add/delete routes, add/update/delete labels, office copies, comments, new district.
6. **Red/green change display** in `deliveryenter.asp`: row bold-red when `totpos ≠ priorpos`; `FlagReport` threshold bands 10/20/30/40.
7. **Copyright footer** "COPYRIGHT(C) month-02 USPS" and the "as of" date continue to render (date source changes only in Phase 2).

## Defect catalog (do not reproduce; fix schedule)

| # | Defect | Phase | Fix |
|---|---|---|---|
| 1 | Anonymous access to a site that writes the DB | **1** | App Service Authentication, Entra ID, no anonymous (§10) |
| 2 | Hardcoded server + password in `database.asp`; leaked `machineKey` in `web.config` | **1** | §6.1 `connvars.asp` from pipeline secrets; §6.2 strip machineKey; new login, new password |
| 3 | Dead `sa;REDACTED_LEGACY_USER` connections (Pinebush/Roselle) | **1** | §6.1 shared include |
| 4 | Junk deployed: CDO email test as `routeupdate.asp` (nav links to it as "Update Routes"), `a.asp` ("Kid is a loser"), `test2.asp`, IIS search webbot, aspnet_client, Thumbs.db | **1** | §5 archive/strip; §6.4 repoint Update Routes → `updatedelete.asp` |
| 5 | SQL injection in ~every data page (string concatenation; blacklist `validateInput` bypassable; `sql_execute` helper unused) | **2** | Parameterize all queries through the **existing** `sql_execute` (ADODB.Command) helper or `ADODB.Command` inline; the §7 least-privilege login bounds damage until done |
| 6 | District from cookie set on one page only → implicit `"ANY"` fallback in `deletelabel`/`updatedelete`/`commentsupdate`/`deleteroute` | **2** | Pass district in query string + validate server-side against `DistrictLookup` (the "school/ANY" match loop every page already duplicates — extract into one routine) |
| 7 | `savelabels.asp` zips positional `Request.Form.Item(i)` to recordset rows; `labelamt` un-validated | **2** | One hidden key per label row (`schooldistrict+location`), validated numeric |
| 8 | SP double-execution with no lock (mode switch + every route mutation; two concurrent operators can interleave `TRUNCATE`-equivalent rebuilds) | **2** | Wrap `EXEC` calls in `sp_getapplock 'PostalRebuild'` … release in `database.asp` (single helper), timeout ~10 min; document single-operator assumption until then |
| 9 | `FlagReport` scans the whole table regardless of selected district | **2** | Add district filter (matches the user's expectation; record before/after output in `CONVERSION.md`) |
| 10 | Hardcoded "as of 4/15/2014" (`postaldata.asp`) + hand-edited date on line ~59 of `deliverystat.asp` (ops Step 6) | **2** | Render both from `Delivery.deliveryDate`/`ImportJob.CompletedUtc` — deletes a manual Kudu file edit from the ops procedure |
| 11 | Dead code: `session("code")`, unused FSO object in `FacingSlips.asp`, `if totalcount=0 then totalremainder=100-rs("totpos")` lines immediately overwritten, `Response.Write` of raw SQL in `updatedelete.asp` | **2** | Remove; strip debug SQL echo |
| 12 | Stale links: `deliveryenter` → `postaldata.asp?schooldistrict=`, hardcoded `postal.chasestaging.net` quick links | **2** | Fix targets; relative URLs |
| 13 | `conn`/recordsets never closed (per-request ODBC handle churn) | **2** | `rs.Close`/`conn.Close` in each page's tail (or a shared `endpage.asp` include) |
| 14 | Latent: any future file-upload feature on this classic site landing in `wwwroot`/`Path.GetTempPath()` (wiped on restart/scale-out; races if a job then "moves" it) | **if added** | §6.5: post to a small ASP.NET endpoint calling `BlobClient.UploadAsync`, or VBScript `MSXML2.ServerXMLHTTP` PUT to a per-request `cw` SAS; store the blob URL, never the SAS |

## Identity and authentication

- **App Service Authentication** on `postal-web`: Entra ID tenant app registration, **"Allow unauthenticated requests" OFF**, sign-in action **Login**. Operators sign in with their work/school account; restrict eligible group to the postal-ops group.
- Classic ASP sees the authenticated user in `Request.ServerVariables("REMOTE_USER")`; no page changes needed in Phase 1 (no page renders the user name).
- HTTPS-only enforced at the App Service level; the custom-domain managed certificate covers `postal.syntaxcom.com` and `*.syntaxcom.com`.
- No client certificates, no Windows auth (the browser doesn't present domain creds to App Service Authentication the way old IIS did).
- The site's **database** login is the fixed `postalweb` SQL user for every user — same as today's shared `syntaxpostal`. Per-user DB accounts are out of scope; audit is supplied by SQL Audit + App Insights instead.

## Environment and configuration

| Setting | Value |
|---|---|
| App name / plan | `postal-web`, Windows, B1+ (shared plan with the importer allowed if it runs Windows) |
| Runtime stack | .NET 4.8 (Windows) |
| Platform bits / pipeline | **32 Bit / Classic** |
| Default document | `index.asp` |
| App Service Authentication | Entra ID, anonymous off |
| App settings | **none required for the site** (connection string deliberately *not* an app setting — classic ASP can't read it; see §6.1). `APPINSIGHTS_CONNECTION` via the standard instrumentation key if not auto-injected. |
| Secrets (CI/CD variable group, pipeline-only) | `POSTAL_DB_SERVER`, `POSTAL_DB_NAME`, `POSTAL_DB_USER=new login postalweb`, `POSTAL_DB_PASSWORD=fresh, Key Vault-backed` |
| SQL firewall | Allow Azure Services (+ the legacy VM IP range only during cutover) |
| Monitoring | App Insights; alert 5xx > 5 in 5 min; SQL Audit on |

## Cutover plan

1. **Stage first**: deploy to a `postal-staging-…azurewebsites.net` (or second slot) instance pointed at a **copy** of the database. Run the full acceptance matrix (§13) against real data.
2. **Import side**: `spec.md`'s importer runs against the same Azure SQL; do one real monthly import through the new pipeline **before** cutting the site, so the site's first live read on Azure is post-import.
3. **Cut DNS**: `postal.syntaxcom.com` CNAME → `postal-web`. Keep the legacy VM (`69.20.14.96`, SQL `REDACTED_INTERNAL_IP`) warm for **two full import cycles**.
4. **Rollback**: repoint CNAME back to the legacy VM; no data migration exists in the reverse direction except the `District*` tables — sync rule during the warm window: legacy VM is read-only; all edits go to Azure.
5. **Decommission** legacy VM + SQL after two clean months; update `postal instructions.txt` (drop FTP/Remote-Desktop steps 1–2, Step 6 becomes automatic in Phase 2).

## Acceptance criteria

- **Page parity**: every §9 behavior reproduced; for `printdata`, `facingslipsHTML` (+ both district variants), capture before/after print preview screenshots of the same month's data and diff-verify line order, `ECRWSS` markers, page breaks.
- **Mode switch**: after `res`/`both` toggle, `deliveryenter` and `postalss` read the correct table; SPs executed (SQL Profiler/Query Store shows both `EXEC`s); 90-second wait message present.
- **Mutation round-trips**: add/duplicate/delete a throwaway district + routes + labels + office copies + comments; each reflects on its read page; `District*` row counts reconcile.
- **Security**: unauthenticated request → Entra sign-in (not a 200); `curl` from a non-allowlisted network → HTTPS redirect; parameter probe (`district' OR 1=1--`) on every input returns validation error/empty, not a stack trace (Phase 1: bounded by least-priv login; Phase 2: parameterized).
- **Injection regression tests** (Phase 2): one automated pass per page against the §5 list.
- **Observability**: an induced 500 appears in App Insights with request ID; no credentials in the deployed zip (scan artifact).
- **Upload path (only if §6.5 is enabled)**: a test upload lands in the `syntaxstoragecontainer1` container with the correct name/size, the page stores the blob URL (SAS nowhere in DB or logs), and nothing was written to `wwwroot`/temp.

## `CONVERSION.md` entry points (record as facts)

- Chose lift & shift over .NET rewrite — reasons; hosting matrix from `syntax-webapp.txt` (Windows / 32-bit / Classic pipeline).
- SVN-to-source-control decision (export script vs repo import) and `backup/` retention.
- `postal.txt` rename decision; which of `changemode.asp`/`mode.asp` survived; `saveroute` vs `addnewroute` live path; Roselle page retirement decision.
- Name/district mismatches kept as legacy: `facingslipspinebush.asp`→WESTBURY, `facingslipsroselle.asp`→deerpark.
- `NewDistrict.asp` rebuilds only `Postalwebboth` (preserved asymmetry).
- Volatility of manual `totpos` overrides (overwritten by next import) — operator communication item.
- Upload-path decision, if ever needed: none / ASP.NET endpoint `UploadAsync` (recommended) / pure-VBScript `MSXML2.ServerXMLHTTP` PUT with per-request `cw` SAS — and its rationale.
- Warm-window duration, legacy decommission date, ops-procedure revision.

## Appendix A — encoded form-value formats

- `deletechoose.asp` / `chooseroute` values (and `updatedelete.asp` input names — same grammar):
  `SUBSTRING(1,4)=routeid, (5,5)=zipcode, (10..)=postoffice`; exception `routeid prefix "BOXE"`: `(1,5)=routeid(5 chars "BOXES"), (6,5)=zipcode, (11..)=postoffice`.
- `FlagReport` value→threshold map: `10→10, 20→20, 30→30, else→40`.
- `deliveryenter` zebra/2-pass render and `postalss` Boxes-roll must keep identical ordering `ORDER BY postoffice, zipcode, routeid`.

## Appendix B — stored-procedure calls from the site (all must keep working)

| Caller | SP(s) |
|---|---|
| `changemode.asp`/`mode.asp` | `Postalweb` (res) **or** `Postalwebboth` (both) |
| `addnewroute.asp` | `Postalwebboth` then `Postalweb` |
| `deletechoose.asp` | `Postalwebboth` then `Postalweb` |
| `NewDistrict.asp` | `Postalwebboth` only |
| `updatedelete.asp` | none (direct `UPDATE` on the web tables — intentionally bypasses SPs) |
