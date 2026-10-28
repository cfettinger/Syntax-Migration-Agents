$source = "D:\Webs\Syntax\syntaxintranet\trunk\web\"
$target = "D:\Webs\Syntax\syntaxintranet\migration\web\"

# Create target directory if it doesn't exist
if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host "Created target directory: $target"
}

$copiedCount = 0

# List of individual ASP files to copy
$files = @(
    "database.asp", "global.asa", "Default.asp", "index.asp", "index1.asp", "index2.asp",
    "admin.asp", "useradmin.asp", "useradminupdate.asp", "checklogin.asp", "checkfirstlogin.asp",
    "stafflogin.asp", "logout.asp", "error.asp", "nav.asp", "navAdmin.asp", "navEmployee.asp",
    "navLocalAdmin.asp", "navLocalClient.asp", "navLocalExpense.asp", "navLocalJob.asp",
    "navLocalMiles.asp", "navLocalTime.asp", "navLocalUserAdmin.asp", "addclient.asp",
    "chooseclient.asp", "clientlist.asp", "editclient.asp", "saveclient.asp", "validateclient.asp",
    "addjob.asp", "editjob.asp", "savejob.asp", "listjobs.asp", "dailyjoblist.asp",
    "dailyviewall.asp", "displayview.asp", "displayview_t2c.asp", "print_displayview_t2c.asp",
    "print_schedule.asp", "addhours.asp", "edithours.asp", "entertime.asp", "viewhours.asp",
    "viewhours_t2c.asp", "printhours.asp", "addexpense.asp", "enterExpense.asp",
    "displayexpense.asp", "viewexpense.asp", "printexpense.asp", "addmiles.asp",
    "entermiles.asp", "displaymiles.asp", "viewmiles.asp", "printmiles.asp",
    "deleteEmployee.asp", "updateEmployee.asp", "contracts.asp", "jobdescriptions.asp",
    "styles.css", "Web.config"
)

# Copy individual files
Write-Host "Copying individual files..."
foreach ($file in $files) {
    $srcPath = Join-Path $source $file
    $tgtPath = Join-Path $target $file
    
    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination $tgtPath -Force
        $copiedCount++
        Write-Host "  [OK] $file"
    } else {
        Write-Host "  [MISS] $file (not found)"
    }
}

# Directories to copy recursively
$directories = @(
    "css",
    "images",
    "includes",
    "dropdown",
    "calendar",
    "announcements",
    "expense",
    "leadlog",
    "scripts"
)

Write-Host "`nCopying directories..."

# Copy css directory
$cssSource = Join-Path $source "css"
if (Test-Path $cssSource) {
    Copy-Item -Path $cssSource -Destination (Join-Path $target "css") -Recurse -Force
    $cssCount = (Get-ChildItem -Path (Join-Path $target "css") -Recurse -File | Measure-Object).Count
    $copiedCount += $cssCount
    Write-Host "  [OK] css\ ($cssCount files)"
}

# Copy images directory
$imagesSource = Join-Path $source "images"
if (Test-Path $imagesSource) {
    Copy-Item -Path $imagesSource -Destination (Join-Path $target "images") -Recurse -Force
    $imgCount = (Get-ChildItem -Path (Join-Path $target "images") -Recurse -File | Measure-Object).Count
    $copiedCount += $imgCount
    Write-Host "  [OK] images\ ($imgCount files)"
}

# Copy includes directory
$includesSource = Join-Path $source "includes"
if (Test-Path $includesSource) {
    Copy-Item -Path $includesSource -Destination (Join-Path $target "includes") -Recurse -Force
    $incCount = (Get-ChildItem -Path (Join-Path $target "includes") -Recurse -File | Measure-Object).Count
    $copiedCount += $incCount
    Write-Host "  [OK] includes\ ($incCount files)"
}

# Copy dropdown directory
$dropdownSource = Join-Path $source "dropdown"
if (Test-Path $dropdownSource) {
    Copy-Item -Path $dropdownSource -Destination (Join-Path $target "dropdown") -Recurse -Force
    $dropCount = (Get-ChildItem -Path (Join-Path $target "dropdown") -Recurse -File | Measure-Object).Count
    $copiedCount += $dropCount
    Write-Host "  [OK] dropdown\ ($dropCount files)"
}

# Copy calendar directory
$calendarSource = Join-Path $source "calendar"
if (Test-Path $calendarSource) {
    Copy-Item -Path $calendarSource -Destination (Join-Path $target "calendar") -Recurse -Force
    $calCount = (Get-ChildItem -Path (Join-Path $target "calendar") -Recurse -File | Measure-Object).Count
    $copiedCount += $calCount
    Write-Host "  [OK] calendar\ ($calCount files)"
}

# Copy announcements directory
$announcementsSource = Join-Path $source "announcements"
if (Test-Path $announcementsSource) {
    Copy-Item -Path $announcementsSource -Destination (Join-Path $target "announcements") -Recurse -Force
    $annCount = (Get-ChildItem -Path (Join-Path $target "announcements") -Recurse -File | Measure-Object).Count
    $copiedCount += $annCount
    Write-Host "  [OK] announcements\ ($annCount files)"
}

# Copy expense directory
$expenseSource = Join-Path $source "expense"
if (Test-Path $expenseSource) {
    Copy-Item -Path $expenseSource -Destination (Join-Path $target "expense") -Recurse -Force
    $expCount = (Get-ChildItem -Path (Join-Path $target "expense") -Recurse -File | Measure-Object).Count
    $copiedCount += $expCount
    Write-Host "  [OK] expense\ ($expCount files)"
}

# Copy leadlog directory (excluding old files)
$leadlogSource = Join-Path $source "leadlog"
if (Test-Path $leadlogSource) {
    Copy-Item -Path $leadlogSource -Destination (Join-Path $target "leadlog") -Recurse -Force
    # Remove excluded leadlog files
    $excludedLeadlog = @("test.asp", "company_old.asp", "displaycontacts_old.asp", "editcontact_old.asp", "index_old.asp", "newcontact_old.asp")
    foreach ($file in $excludedLeadlog) {
        $filePath = Join-Path $target "leadlog" $file
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
            $copiedCount--
        }
    }
    $leadCount = (Get-ChildItem -Path (Join-Path $target "leadlog") -Recurse -File | Measure-Object).Count
    Write-Host "  [OK] leadlog\ ($leadCount files after exclusions)"
}

# Copy scripts directory with selective subdirectories
$scriptsSource = Join-Path $source "scripts"
if (Test-Path $scriptsSource) {
    New-Item -ItemType Directory -Path (Join-Path $target "scripts") -Force | Out-Null
    Copy-Item -Path (Join-Path $scriptsSource "jquery.js") -Destination (Join-Path $target "scripts") -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $scriptsSource "jquery.tablesorter.js") -Destination (Join-Path $target "scripts") -Force -ErrorAction SilentlyContinue
    
    if (Test-Path (Join-Path $scriptsSource "jscalendar")) {
        New-Item -ItemType Directory -Path (Join-Path $target "scripts\jscalendar") -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptsSource "jscalendar") -Destination (Join-Path $target "scripts\jscalendar") -Recurse -Force
    }
    
    if (Test-Path (Join-Path $scriptsSource "jquery-ui-timepicker")) {
        New-Item -ItemType Directory -Path (Join-Path $target "scripts\jquery-ui-timepicker") -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptsSource "jquery-ui-timepicker") -Destination (Join-Path $target "scripts\jquery-ui-timepicker") -Recurse -Force
    }
    
    # Copy jquery-ui-1.10.3.custom but exclude development-bundle and index.html
    if (Test-Path (Join-Path $scriptsSource "jquery-ui-1.10.3.custom")) {
        $jquitarget = Join-Path $target "scripts\jquery-ui-1.10.3.custom"
        New-Item -ItemType Directory -Path $jquitarget -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptsSource "jquery-ui-1.10.3.custom") -Destination $jquitarget -Recurse -Force
        # Remove excluded files
        Remove-Item -Path (Join-Path $jquitarget "development-bundle") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $jquitarget "index.html") -Force -ErrorAction SilentlyContinue
    }
    
    $scriptCount = (Get-ChildItem -Path (Join-Path $target "scripts") -Recurse -File | Measure-Object).Count
    $copiedCount += $scriptCount
    Write-Host "  [OK] scripts\ ($scriptCount files)"
}

# Remove all Thumbs.db files from the target tree
Write-Host "`nRemoving Thumbs.db files..."
$thumbsFiles = Get-ChildItem -Path $target -Recurse -Name "Thumbs.db" -ErrorAction SilentlyContinue
$thumbsCount = 0
foreach ($thumbsFile in $thumbsFiles) {
    $fullPath = Join-Path $target $thumbsFile
    Remove-Item $fullPath -Force -ErrorAction SilentlyContinue
    $thumbsCount++
    Write-Host "  Removed: $thumbsFile"
}

if ($thumbsCount -eq 0) {
    Write-Host "  No Thumbs.db files found"
} else {
    Write-Host "  Removed $thumbsCount Thumbs.db file(s)"
    $copiedCount -= $thumbsCount
}

Write-Host "`n=========================================="
Write-Host "Migration complete!"
Write-Host "Total files copied: $copiedCount"
Write-Host "Target directory: $target"
Write-Host "=========================================="
