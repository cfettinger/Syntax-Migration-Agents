# Task: Optimize Bicep Template - Single App Service Plan for Function + Web App

**Title:** Share single Microsoft.Web/serverfarms resource between Function App and Web App  
**Owner:** backend dev / DevOps  
**Branch:** postal-azure-function-worker  
**Effort:** 0.5 hours  
**Priority:** HIGH (unblocks B1 deployment blocker)  
**Status.md Update:** Move from W4 blocker to ready-to-deploy

---

## Problem & Solution

**Current Issue:**
- Bicep template creates TWO separate App Service Plans: one for Web App, one for Function App
- B1 quota limit in subscription is 0
- Attempting to deploy 2 x B1 plans requires 2 quota, fails immediately

**Solution:**
- Create ONE `Microsoft.Web/serverfarms` resource (B1 tier)
- Reference same plan from BOTH Web App (`Microsoft.Web/sites`) and Function App (`Microsoft.Web/sites`)
- Only requires 1 quota unit → deployment succeeds

**Key Constraint:**
- Both app types can coexist on same B1 plan (no conflict)
- Function App (isolated) and Web App (ASP.NET) use same underlying compute

---

## Implementation Steps

### Step 1: Review Current Bicep Structure
**File:** `infra/bicep/main.bicep`  
**Identify:**
1. Current Web App plan resource (look for `Microsoft.Web/serverfarms` with specific name/SKU)
2. Current Function App plan resource (separate `Microsoft.Web/serverfarms`)
3. Web App resource that references its plan
4. Function App resource that references its plan

**Example current structure:**
```bicep
// WEB APP PLAN
resource webAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'postal-web-plan'
  location: location
  sku: { name: 'B1', tier: 'Standard', capacity: 1 }
  kind: 'linux'
}

// FUNCTION APP PLAN
resource funcAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'postal-func-plan'
  location: location
  sku: { name: 'B1', tier: 'Standard', capacity: 1 }
  kind: 'windows'
}

// WEB APP
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  kind: 'app'
  properties: {
    serverFarmId: webAppServicePlan.id  // <- references webAppServicePlan
  }
}

// FUNCTION APP
resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: funcAppServicePlan.id  // <- references funcAppServicePlan
  }
}
```

### Step 2: Consolidate to Single Plan
**Goal:** Replace both plan resources with one shared plan

```bicep
// SINGLE SHARED APP SERVICE PLAN (for both Web App and Function App)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'postal-app-service-plan'  // Single, descriptive name
  location: location
  sku: { 
    name: 'B1'
    tier: 'Standard'
    capacity: 1 
  }
  kind: 'linux'  // Keep as 'linux' or use 'app,functionapp' hybrid
  properties: {
    reserved: true  // For Linux (if using Linux kind)
  }
}

// WEB APP (references SHARED plan)
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'  // Match plan OS
  properties: {
    serverFarmId: appServicePlan.id  // <- references shared plan
    // ... rest of config
  }
}

// FUNCTION APP (references SAME shared plan)
resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp,linux'  // Match plan OS
  properties: {
    serverFarmId: appServicePlan.id  // <- same shared plan
    // ... rest of config
  }
}
```

### Step 3: Update Parameters (if applicable)
**File:** `infra/bicep/main.parameters.json`

If you have separate plan SKU parameters, consolidate:

**Before:**
```json
{
  "appServicePlanSku": "B1",
  "webAppPlanName": "postal-web-plan",
  "funcAppPlanName": "postal-func-plan"
}
```

**After:**
```json
{
  "appServicePlanSku": "B1",
  "appServicePlanName": "postal-app-service-plan"
}
```

### Step 4: Update Bicep Parameters & Variables
**In `main.bicep` header:**

**Before:**
```bicep
param webAppPlanName string = 'postal-web-plan'
param funcAppPlanName string = 'postal-func-plan'
param appServicePlanSku string = 'B1'
```

**After:**
```bicep
param appServicePlanName string = 'postal-app-service-plan'
param appServicePlanSku string = 'B1'
```

### Step 5: Validation & Testing
**Local validation:**
```bash
cd migration
az bicep build --file infra/bicep/main.bicep
```

**Expected output:**
- Exit code: 0
- Warnings: Only BCP081 (expected, for storage queues) or none
- **Important:** Template should now reference only ONE `Microsoft.Web/serverfarms` resource

**Verify plan count:**
```bash
# Count serverfarms resources in built template
az bicep build --file infra/bicep/main.bicep --outfile main.json
(Get-Content main.json | ConvertFrom-Json).resources | Where-Object {$_.type -eq 'Microsoft.Web/serverfarms'} | Measure-Object
# Expected: Count = 1
```

### Step 6: Deploy to Azure (post-fix)
**After Bicep is updated and validated:**

```bash
cd migration
azd provision
azd deploy
```

**Or manually:**
```bash
az deployment group create \
  -g Syntax \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json \
  --parameters sqlAdminPassword='<from-keyvault>' \
  --parameters appServicePlanSku='B1'
```

**Expected behavior:**
- Deployment should succeed (only requires 1 B1 quota, not 2)
- Single plan created in Azure Portal
- Both apps visible under same plan in Azure Portal

---

## Acceptance Criteria

- [ ] **Bicep compiles:** `az bicep build` exit 0, no errors
- [ ] **Single plan resource:** Only 1 `Microsoft.Web/serverfarms` in built template
- [ ] **Plan reference count:** Both Web App and Function App `serverFarmId` properties reference same plan
- [ ] **Parameter aligned:** `appServicePlanName` parameter used consistently
- [ ] **No hardcoded names:** All resource names use parameters (no duplicates)
- [ ] **Deployment succeeds:** Run `az deployment group create` → Status: Succeeded (not quota error)
- [ ] **Azure verification:** Query deployed plan → shows both apps listed
  ```bash
  az appservice plan show -g Syntax -n postal-app-service-plan \
    --query "{name:name, sku:sku, numberOfSites:numberOfSites}"
  ```
  Expected: `numberOfSites: 2` (Web App + Function App)

---

## Files to Change

1. **`infra/bicep/main.bicep`**
   - Delete: `webAppServicePlan` resource definition
   - Delete: `funcAppServicePlan` resource definition
   - Add: Single `appServicePlan` resource
   - Update: Web App `serverFarmId` → reference `appServicePlan.id`
   - Update: Function App `serverFarmId` → reference `appServicePlan.id`
   - Update: Parameters section (consolidate SKU/name params)

2. **`infra/bicep/main.parameters.json`**
   - Remove: `webAppPlanName` (if present)
   - Remove: `funcAppPlanName` (if present)
   - Add/Consolidate: `appServicePlanName` parameter
   - Verify: `appServicePlanSku` present

---

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| App Service Plans | 2 (separate) | 1 (shared) |
| B1 Quota Required | 2 | **1** ✅ |
| Cost (compute) | 2 × B1 | **1 × B1** (50% reduction) |
| TCO Impact | Higher | **Lower** ✅ |
| Deployment Blocker | Yes (quota) | **No** (unblocked) ✅ |
| Deployment Time | N/A | Faster (fewer resources) ✅ |

---

## Rollback / Revert Plan

If issues arise post-deployment:

```bash
# Retain current commit
git log --oneline -1

# Revert Bicep changes
git revert HEAD

# Rebuild & redeploy (to restore original 2-plan setup)
az bicep build --file infra/bicep/main.bicep
az deployment group create ... # Deploy with reverted template
```

---

## Security & Architecture Notes

✅ **Security unchanged:**
- Managed identity roles still applied to both apps
- SQL connection still uses DefaultAzureCredential
- Storage access still via SAS tokens

✅ **Performance:**
- Single B1 plan → shared compute (acceptable for dev/test)
- No cross-app interference (isolated worker processes)
- Can scale plan later (B2/B3/P1) without code changes

✅ **Migration path:** 
- For production, can deploy to higher tier (P1/P2) with same template
- Shared plan pattern scales to production if needed

---

## Next Steps After Completion

1. ✅ Update Bicep (`main.bicep` + `main.parameters.json`)
2. ✅ Validate locally: `az bicep build` exit 0
3. ✅ Commit with message:
   ```
   feat(bicep): consolidate Function + Web App into single shared App Service Plan

   - Replaces two separate Microsoft.Web/serverfarms resources with one
   - Reduces B1 quota requirement from 2 to 1 (unblocks deployment)
   - Both apps reference same plan via serverFarmId
   - Validated: az bicep build exit 0
   - Cost: 50% reduction on compute (B1 unit)
   ```
4. ✅ Execute P0 deployment (post-quota-fix or with Free/F1 workaround first for testing)
5. ✅ Verify in Azure: `az appservice plan show -g Syntax -n postal-app-service-plan`
6. ✅ Update `Postal/status.md`: Move W4 from blocker to ready-to-deploy

---

## Effort Breakdown

- Identify & review current plan resources: **0.1h**
- Consolidate to single resource + update references: **0.2h**
- Update parameters file: **0.05h**
- Local validation (`az bicep build`): **0.05h**
- Commit + update status tracker: **0.05h**
- **Total: 0.5 hours**

---

## Owner Handoff

**Assigned to:** Backend dev or DevOps  
**Prerequisite:** Access to `D:\Webs\Syntax\PostalExe\migration` repo  
**Outcome:** Unblocks W4 deployment; quota requirement reduced 50%  
**Status.md Entry (on completion):**
```
- ✅ W4 Bicep optimization — consolidated App Service Plan (2026-10-20T[time]Z). 
  Single Microsoft.Web/serverfarms resource for both Web App + Function App. 
  B1 quota requirement: 2 → **1**. 
  Files: infra/bicep/main.bicep, infra/bicep/main.parameters.json. 
  Validation: `az bicep build` exit 0. 
  Branch: postal-azure-function-worker. 
  Commit: [hash].
  Agent: Backend Dev (cfettinger).
```
