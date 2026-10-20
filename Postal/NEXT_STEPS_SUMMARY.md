# Postal Importer Migration: Next Steps Summary
**Generated:** 2026-10-20T11:30:00Z  
**Agent:** Postal Migrator - GitHub Copilot (cfettinger)  
**Status:** Code-complete locally ✅; Bicep templates validated ✅; Azure infrastructure present ✅; **Awaiting deployment quota resolution**

---

## Session Summary (2026-10-20)

### Work Completed
1. ✅ **Managed Identity Infrastructure Validation (8E1)**  
   - Verified `syntax-main-id` (User-Assigned MI, Principal: a9c0e286-ecd6-4c1b-beb4-ead5fdb75481) active  
   - Confirmed Storage Blob Data Contributor + Storage Blob Delegator roles on `syntaxstoragev2`  
   - Verified Azure SQL `Postal` database online with AllowAllAzureIps firewall rule  
   - Validated Bicep template: `az bicep build` exit 0, 0 errors  

2. ✅ **Status Tracker Consolidation**  
   - Updated `Postal/status.md` with validation evidence  
   - Moved Architecture Overview to `infra/README.md` (ops-focused)  
   - Refreshed "Next Immediate Steps" with clear P0–P8 priority breakdown  
   - Added timestamps, agent identifiers, and evidence links  

3. ✅ **Documentation Updates**  
   - Commit `2c154b4`: priority tasks with acceptance criteria  
   - Commit `27db4ba`: Azure deployment status + managed identity validation  

---

## Current State: Code Readiness

| Component | Status | Notes |
|-----------|--------|-------|
| **API (Postal.Api)** | ✅ Ready | `/api/imports`, `/api/imports/{jobId}/complete`, `/api/imports/{jobId}/sas-refresh` implemented; local tests pass |
| **Function Worker (Postal.Function)** | ✅ Ready | Fixed-width/CRLF parsing, atomic claims, bulk insert (batch 1000), resume logic, stored procs (Postalweb/Postalwebboth), telemetry |
| **Bicep/azd Templates** | ✅ Ready | `infra/bicep/main.bicep`, `main.parameters.json`, `azure.yaml`, GitHub Actions OIDC workflow committed |
| **Local Smoke Test** | ✅ Complete | sample.wrk (309 B) imported end-to-end; ImportJob Succeeded; verified 2026-10-17 |
| **SQL Scripts** | ✅ Ready | `infra/sql/003`, `004`: postalweb user + least-privilege grants (pending ops execution) |

---

## Current Blocker: B1 Quota Exhausted

**Issue:** Bicep deployment attempt failed with:  
```
SubscriptionIsOverQuotaForSku: Subscription quota for resource type 'cores' has been reached.
(Current Limit: 0, Required: 1 for B1 AppServicePlan tier)
```

**Impact:** Cannot deploy Function App or Web App to Azure yet.

**Resolution (choose one):**

1. **Recommended:** Request Azure Support quota increase  
   - Target: +1 B1 AppServicePlan instance  
   - Expected wait: 24–48 hours  
   - Effort: 0.5 hours (submit ticket)  

2. **Workaround (testing only):** Modify Bicep to deploy to Free (F1) or Shared (D1) tier  
   - Edit: `infra/bicep/main.bicep` lines {appServicePlanSkuName, appServicePlanSkuTier}  
   - Change: `B1` → `F1` (free) or `D1` (shared)  
   - Effort: 0.25 hours  
   - **Caveat:** Free/Shared are not production-grade; use for validation only  

3. **Alternative:** Check if B2/B3 quota available  
   - Verify: `az vm list-usage --location eastus --query "[?name.value=='cores'].currentValue"` (approx current usage)  
   - May need cost justification  

---

## Next Actionable Steps (Priority Order)

### **P0: CRITICAL – Resolve Quota Blocker** (Owner: ops/DevOps)
- Submit Azure Support ticket OR modify Bicep to F1 tier  
- **Unblocks:** P1–P8 (all remaining work)  
- **Effort:** 0.5–2 hours (depends on quota increase decision)  
- **Evidence:** Deployment success or F1 Bicep modification in commit  

### **P1: SQL User Provisioning (W3)** (Owner: ops/DBA) — Post-quota fix
- Connect to Postal DB as SQL admin  
- Execute: `infra/sql/003-create-postalweb-login.sql` (creates login)  
- Execute: `infra/sql/004-grant-postalweb-permissions.sql` (INSERT/EXECUTE grants)  
- Verify: `SELECT * FROM sys.database_principals WHERE name='postalweb'`  
- **Effort:** 0.5 hours  
- **Evidence:** Script output + permission query results in status.md  

### **P2: Deploy Function App + Web App (W4)** (Owner: DevOps/Platform) — After P0
- Run: `azd provision` and `azd deploy` (or manual `az deployment group create`)  
- Provide: `sqlAdminPassword` from Key Vault at deploy time  
- **Effort:** 1 hour + quota resolution wait time  
- **Evidence:** `az webapp show` + `az functionapp show` output  

### **P3: Validate Managed Identity (W5)** (Owner: DevOps) — After P2
- Query: `az webapp identity show -g Syntax -n postal-api`  
- Query: `az functionapp identity show -g Syntax -n postal-import`  
- Verify: Identity principal IDs match or include `a9c0e286-ecd6-4c1b-beb4-ead5fdb75481`  
- **Effort:** 0.25 hours  

### **P4: Test SQL Permissions (W6)** (Owner: backend dev/ops) — After P1 + P2
- Deploy small test: acquire SQL token via `DefaultAzureCredential`  
- Run dry-run import to Postal DB  
- Verify: INSERT/EXECUTE succeed; no permission errors  
- **Effort:** 1.5 hours  
- **Evidence:** Function App logs (Application Insights), ImportJob Succeeded status  

### **P5: End-to-End Azure Smoke Test (W7)** (Owner: backend dev) — After P2–P4
- POST to `https://<postal-api>.azurewebsites.net/api/imports` with sample.wrk  
- Browser upload via SAS URL  
- POST `/complete` → trigger Function → parse → bulk insert → stored procs  
- Verify: ImportJob Succeeded; Delstat row created  
- **Effort:** 1 hour  
- **Evidence:** Function logs, DB results, response JSON  

### **P6–P8: Testing, Docs, Handoff** (Post-deployment)
- P6: Automated unit + integration tests (2–3 hours)  
- P7: README + ops runbook (1.5 hours)  
- P8: Website deployment (separate project)  

---

## Key Artifacts & References

### Status Tracker
- **Location:** `D:\Projects\Syntax-Migration-Agents\Postal\status.md`  
- **Last commit:** `2c154b4` (2026-10-20T11:30:00Z)  
- **Sections:** Completed (✅ 9 items), In Progress (W3–W7), Next Steps (P0–P8)  

### Specification
- **Design Spec:** `spec.md` (Syntax-Migration-Agents)  
- **API Spec:** `websitespec.md` (lift & shift)  
- **Ops Guide:** `infra/README.md` (migration repo)  

### Bicep & Deployment
- **Template:** `D:\Webs\Syntax\PostalExe\migration\infra\bicep\main.bicep`  
- **Parameters:** `infra\bicep\main.parameters.json` (non-secrets only)  
- **Azd config:** `azure.yaml` + `.github\workflows\deploy-api-function.yml`  

### Code (Branch: postal-azure-function-worker)
- **API:** `src/Postal.Api/Program.cs` (POST /api/imports + SAS minting)  
- **Function:** `src/Postal.Function/ImportWorker.cs` (parse, bulk insert, procs)  
- **Repositories:** `src/Postal.Api/Data/ImportJobRepository.cs`  
- **Services:** `src/Postal.Api/Services/BlobSasService.cs`  

### Test Data
- **Sample generator:** `testdata/generate_sample.ps1` (309 B valid Delstat record)  

### Azure Infrastructure (Verified Online)
- **Resource Group:** `Syntax` (eastus and other regions)  
- **SQL Server:** `syntax-sql` (Postal DB online)  
- **Storage:** `syntaxstoragev2` (Blob + Queue endpoints available)  
- **Managed Identity:** `syntax-main-id` (User-Assigned, Principal a9c0e286-ecd6-4c1b-beb4-ead5fdb75481)  
- **App Service Plan:** `syntax-app-service` (B1, reserved; no apps deployed yet)  

---

## Important Notes

### Security Posture
- ✅ No secrets committed to repo  
- ✅ `local.settings.json` is .gitignore'd; dev-only  
- ✅ SQL admin password injected via Key Vault at deploy time (CI/CD)  
- ✅ Managed identity auth throughout (no inline credentials in prod)  
- ✅ OIDC federated auth in GitHub Actions (no long-lived tokens)  

### Resume Logic & Idempotency
- Function atomically claims job in DB (conditional update)  
- RowsWritten tracking: only truncate Delstat if RowsWritten == 0 (first run)  
- Visibility renewal ensures no message loss during long operations  
- Can safely re-run same job if Function crashes mid-import  

### Migration vs. Rewrite
- **Not porting WinForms UI** — migrating to Azure serverless pipeline  
- **No legacy VB.NET code in production** — all replaced with .NET 8 C#  
- **Website (ASP.NET 3.5) follows later** — already assessed for lift & shift  

---

## Quick Reference: CLI Commands

**Verify Managed Identity:**
```bash
az identity show -g Syntax -n syntax-main-id
az role assignment list --assignee-object-id a9c0e286-ecd6-4c1b-beb4-ead5fdb75481 --scope <storage-scope>
```

**Check Azure SQL:**
```bash
az sql db show -g Syntax -s syntax-sql -n Postal
az sql server firewall-rule list -g Syntax -s syntax-sql
```

**Deploy (after P0):**
```bash
cd migration
azd provision
azd deploy
```

**Query SQL Permissions (after P1):**
```sql
SELECT * FROM sys.database_principals WHERE name='postalweb';
SELECT permission_name FROM sys.database_permissions 
  WHERE grantee_principal_id = (SELECT principal_id FROM sys.database_principals WHERE name='postalweb');
```

---

## Contact & Handoff

- **Postal Migrator Agent:** GitHub Copilot (cfettinger, harness: Microsoft)  
- **For quota increase:** ops/Azure admin  
- **For SQL provisioning:** DBA / ops  
- **For deployment:** DevOps / platform engineer  
- **For testing:** backend dev / QA  
- **Tracking:** Update `Postal/status.md` on each task completion  

---

**Status:** Code ✅ Ready · Infrastructure ✅ Verified · Quota ❌ Blocker · Next: P0 (resolve quota) → P1–P7 (deploy & validate)
