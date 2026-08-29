#Requires -Version 5.1
# ============================================================================
# Deploy — Unify Task Assignment, Acceptance, Roles, and Notifications
# Target: TEST only (test.erpnext.am)
# ============================================================================
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# --- Credentials (from export.ps1) ---
$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data }
    catch { return $null }
}
function Upsert-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Existing = Get-ErpDoc $DocType $Name
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    if ($Existing) {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30 | Out-Null
        return [pscustomobject]@{ action = "updated"; name = $Name }
    }
    $Body.name = $Name
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    $Created = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30).data
    return [pscustomobject]@{ action = "created"; name = $Created.name }
}
function Delete-ErpDoc([string]$DocType, [string]$Name) {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Delete -TimeoutSec 30 | Out-Null
        return $true
    } catch { return $false }
}

Write-Host "`n=== Unify Task Assignment, Acceptance, Roles, and Notifications ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode: $Mode`n" -ForegroundColor Yellow

# ============================================================================
# PHASE A: Schema prerequisites
# ============================================================================
Write-Host "--- Phase A: Schema Prerequisites ---" -ForegroundColor Magenta

# Step 1: Add telegram_chat_id custom field on User
Write-Host "`n[A1] telegram_chat_id custom field on User..." -ForegroundColor White
$existingTgField = Get-ErpDoc "Custom Field" "User-telegram_chat_id"
if ($existingTgField) {
    Write-Host "  Already exists." -ForegroundColor DarkGray
} else {
    if ($Mode -eq "Deploy") {
        $tgField = [ordered]@{
            dt = "User"
            fieldname = "telegram_chat_id"
            label = "Telegram Chat ID"
            fieldtype = "Data"
            insert_after = "mobile_no"
            description = "Telegram numeric chat ID for bot notifications"
        }
        $r = Upsert-ErpDoc "Custom Field" "User-telegram_chat_id" $tgField
        Write-Host "  $($r.action): User-telegram_chat_id" -ForegroundColor Green
    } else {
        Write-Host "  WOULD CREATE: User-telegram_chat_id" -ForegroundColor Yellow
    }
}

# Step 1b: Populate known chat IDs
Write-Host "`n[A1b] Populate known Telegram chat IDs..." -ForegroundColor White
$chatIds = @{
    "levonaghinyan77@gmail.com" = "1908277721"
    "sahakyan.oli1998@gmail.com" = "6563165623"
    "vagramyankaren@gmail.com" = "697289441"
    "ly.aghayan@gmail.com" = "909299151"
    "karapetyansev@gmail.com" = "838790562"
    "artursemerjyan91@gmail.com" = "807759949"
    "ghahramanyann@gmail.com" = "1301686056"
    "m.nersisyan93@gmail.com" = "993000488"
    "artakn7@gmail.com" = "1388206182"
}
foreach ($email in $chatIds.Keys) {
    $user = Get-ErpDoc "User" $email
    if (-not $user) {
        Write-Host "  User $email not found - skipping" -ForegroundColor DarkYellow
        continue
    }
    $currentId = $null
    try { $currentId = $user.telegram_chat_id } catch {}
    if ($currentId -and $currentId -eq $chatIds[$email]) {
        Write-Host "  $email already set to $currentId" -ForegroundColor DarkGray
    } else {
        if ($Mode -eq "Deploy") {
            $body = @{ telegram_chat_id = $chatIds[$email] }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/User/$(Enc $email)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Set $email -> $($chatIds[$email])" -ForegroundColor Green
        } else {
            Write-Host "  WOULD SET $email -> $($chatIds[$email])" -ForegroundColor Yellow
        }
    }
}

# Step 2: Verify directors.team@example.com exists
Write-Host "`n[A2] Verify directors.team@example.com..." -ForegroundColor White
$directorsUser = Get-ErpDoc "User" "directors.team@example.com"
if ($directorsUser) {
    if ($directorsUser.enabled -eq 0) {
        Write-Host "  Exists but DISABLED - enabling" -ForegroundColor DarkYellow
        if ($Mode -eq "Deploy") {
            $body = @{ enabled = 1 }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/User/$(Enc 'directors.team@example.com')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Enabled directors.team@example.com" -ForegroundColor Green
        } else {
            Write-Host "  WOULD ENABLE directors.team@example.com" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Exists (enabled=1)" -ForegroundColor Green
    }
} else {
    Write-Host "  NOT FOUND - needs to be created" -ForegroundColor Red
    if ($Mode -eq "Deploy") {
        $newUser = @{
            email = "directors.team@example.com"
            first_name = "Directors Team"
            enabled = 1
            user_type = "System User"
            send_welcome_email = 0
            roles = @(@{ role = "Ops - Directors" })
        }
        $json = $newUser | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/User" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Created directors.team@example.com" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR creating user: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Step 2b: Verify office.team@example.com exists
Write-Host "`n[A2b] Verify office.team@example.com..." -ForegroundColor White
$officeUser = Get-ErpDoc "User" "office.team@example.com"
if ($officeUser) {
    Write-Host "  Exists (enabled=$($officeUser.enabled))" -ForegroundColor Green
} else {
    Write-Host "  NOT FOUND - needs to be created" -ForegroundColor Red
    if ($Mode -eq "Deploy") {
        $newUser = @{
            email = "office.team@example.com"
            first_name = "Office Team"
            enabled = 1
            user_type = "System User"
            send_welcome_email = 0
            roles = @(@{ role = "Ops - Order Accepting" }, @{ role = "Ops - Returns" })
        }
        $json = $newUser | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/User" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Created office.team@example.com" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR creating user: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Step 2c: Migrate "Order accepting" tasks to "Order entry"
Write-Host "`n[A2c] Migrate 'Order accepting' tasks..." -ForegroundColor White
try {
    $oaFilters = [uri]::EscapeDataString('[["task_kind","=","Order accepting"]]')
    $oaFields = [uri]::EscapeDataString('["name"]')
    $oaUrl = "${BaseUrl}/api/resource/Task?filters=${oaFilters}" + [char]38 + "fields=${oaFields}" + [char]38 + "limit_page_length=500"
    $oaTasks = (Invoke-RestMethod -Uri $oaUrl -Headers $Headers -Method Get -TimeoutSec 30).data
} catch { $oaTasks = @() }
if ($oaTasks.Count -eq 0) {
    Write-Host "  No tasks with 'Order accepting' found." -ForegroundColor DarkGray
} else {
    Write-Host "  Found $($oaTasks.Count) tasks with 'Order accepting'" -ForegroundColor Yellow
    if ($Mode -eq "Deploy") {
        foreach ($t in $oaTasks) {
            $body = @{ task_kind = "Order entry" }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task/$(Enc $t.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
        }
        Write-Host "  Migrated $($oaTasks.Count) tasks to 'Order entry'" -ForegroundColor Green
    } else {
        Write-Host "  WOULD MIGRATE $($oaTasks.Count) tasks to 'Order entry'" -ForegroundColor Yellow
    }
}

# ============================================================================
# PHASE B+C: Deploy server scripts
# ============================================================================
Write-Host "`n--- Phase B+C: Server Scripts ---" -ForegroundColor Magenta

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"
$ServerScripts = @(
    @{ name = "Task-before-save-policy"; file = "server\Task-before-save-policy.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "dispatch_task_accept"; file = "server\dispatch_task_accept.py"; doctype = ""; event = ""; type = "API"; disabled = 0 },
    @{ name = "task_list_filtered"; file = "server\task_list_filtered.py"; doctype = ""; event = ""; type = "API"; disabled = 0 },
    @{ name = "Task-before-save-lock-unaccepted"; file = "server\Task-before-save-lock-unaccepted.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-before-save-dispatch-gates"; file = "server\Task-before-save-dispatch-gates.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-after-save-other-processing"; file = "server\Task-after-save-other-processing.py"; doctype = "Task"; event = "After Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-Account Details Default Assignment"; file = "server\Task-Account Details Default Assignment.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 1 },
    @{ name = "dispatch_task_queue_backfill"; file = "server\dispatch_task_queue_backfill.py"; doctype = ""; event = ""; type = "API"; disabled = 1 },
    @{ name = "Telegram Task Assignment Notification"; file = "server\Telegram Task Assignment Notification.py"; doctype = "Task"; event = "After Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Telegram Task Status Update"; file = "server\Telegram Task Status Update.py"; doctype = "Task"; event = "After Save"; type = "DocType Event"; disabled = 0 }
)

foreach ($ss in $ServerScripts) {
    $scriptPath = Join-Path $WorkDir $ss.file
    $scriptContent = Get-Content $scriptPath -Raw -Encoding UTF8
    # Strip the header comment block (lines starting with # Name:, # Type:, etc. up to # ---)
    $lines = $scriptContent -split "`n"
    $startIdx = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "# ---") { $startIdx = $i + 1; break }
    }
    $scriptBody = ($lines[$startIdx..($lines.Count - 1)] -join "`n").TrimStart("`n").TrimStart("`r`n")

    Write-Host "`n[$($ss.name)]" -ForegroundColor White
    $existing = Get-ErpDoc "Server Script" $ss.name

    if ($existing) {
        # Detect if Telegram Assignment was previously on ToDo — need to change DocType and Event
        $needsDocTypeChange = $false
        if ($ss.name -eq "Telegram Task Assignment Notification" -and $existing.reference_doctype -ne "Task") {
            $needsDocTypeChange = $true
            Write-Host "  Changing trigger: ToDo After Insert -> Task After Save" -ForegroundColor Cyan
        }

        if ($Mode -eq "Deploy") {
            $body = @{ script = $scriptBody; disabled = $ss.disabled }
            if ($ss.type -eq "DocType Event") {
                $body.reference_doctype = $ss.doctype
                $body.doctype_event = $ss.event
            }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $ss.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            $disabledStr = $(if ($ss.disabled) { " (DISABLED)" } else { "" })
            Write-Host "  Updated$disabledStr" -ForegroundColor Green
        } else {
            $disabledStr = $(if ($ss.disabled) { " (DISABLE)" } else { "" })
            Write-Host "  WOULD UPDATE$disabledStr" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  NOT FOUND on server - script may have a different name" -ForegroundColor Red
    }
}

# ============================================================================
# PHASE D: Deploy client scripts
# ============================================================================
Write-Host "`n--- Phase D: Client Scripts ---" -ForegroundColor Magenta

$ClientScripts = @(
    @{ name = "Task-Accept Start"; file = "client\Task-Accept Start.js"; enabled = 1 },
    @{ name = "Task-Lock Unaccepted"; file = "client\Task-Lock Unaccepted.js"; enabled = 1 },
    @{ name = "Task-Team Queue"; file = "client\Task-Team Queue.js"; enabled = 1 },
    @{ name = "Task-Dispatch Packing Usability"; file = "client\Task-Dispatch Packing Usability.js"; enabled = 1 },
    @{ name = "Task-List Toggle Filters"; file = "client\Task-List Toggle Filters.js"; enabled = 0 },
    @{ name = "Global-Mobile Back Button List"; file = "client\Global-Mobile Back Button List.js"; enabled = 1 },
    @{ name = "Task-Other UI Cleanup"; file = "client\Task-Other UI Cleanup.js"; enabled = 1 },
    @{ name = "Task-Account Details UI Cleanup"; file = "client\Task-Account Details UI Cleanup.js"; enabled = 1 },
    @{ name = "Task-Auto Reload"; file = "client\Task-Auto Reload.js"; enabled = 1 }
)

foreach ($cs in $ClientScripts) {
    $scriptPath = Join-Path $WorkDir $cs.file
    $scriptContent = Get-Content $scriptPath -Raw -Encoding UTF8
    # Strip the header comment block
    $lines = $scriptContent -split "`n"
    $startIdx = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "// ---") { $startIdx = $i + 1; break }
    }
    $scriptBody = ($lines[$startIdx..($lines.Count - 1)] -join "`n").TrimStart("`n").TrimStart("`r`n")

    Write-Host "`n[$($cs.name)]" -ForegroundColor White
    $existing = Get-ErpDoc "Client Script" $cs.name

    if ($existing) {
        if ($Mode -eq "Deploy") {
            $body = @{ script = $scriptBody; enabled = $cs.enabled }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $cs.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            $disabledStr = $(if (-not $cs.enabled) { " (DISABLED)" } else { "" })
            Write-Host "  Updated$disabledStr" -ForegroundColor Green
        } else {
            $disabledStr = $(if (-not $cs.enabled) { " (DISABLE)" } else { "" })
            Write-Host "  WOULD UPDATE$disabledStr" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  NOT FOUND on server - script may have a different name" -ForegroundColor Red
    }
}

# ============================================================================
# PHASE E: Remove custom fields and property setters
# ============================================================================
Write-Host "`n--- Phase E: Schema Cleanup ---" -ForegroundColor Magenta

# Step 24: Remove 4 custom fields from Task
$fieldsToRemove = @(
    "Task-custom_is_team_queue_task",
    "Task-custom_team_queue_role",
    "Task-custom_team_queue_status",
    "Task-custom_team_notified"
)

foreach ($fieldName in $fieldsToRemove) {
    Write-Host "`n[E24] $fieldName" -ForegroundColor White
    $existing = Get-ErpDoc "Custom Field" $fieldName
    if ($existing) {
        if ($Mode -eq "Deploy") {
            $ok = Delete-ErpDoc "Custom Field" $fieldName
            if ($ok) { Write-Host "  DELETED" -ForegroundColor Green }
            else { Write-Host "  FAILED to delete" -ForegroundColor Red }
        } else {
            Write-Host "  WOULD DELETE" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Already gone." -ForegroundColor DarkGray
    }
}

# Step 25: Remove property setters for deleted fields
$psToRemove = @(
    "Task-custom_is_team_queue_task-hidden",
    "Task-custom_team_notified-hidden"
)
foreach ($psName in $psToRemove) {
    Write-Host "`n[E25] Property Setter: $psName" -ForegroundColor White
    $existing = Get-ErpDoc "Property Setter" $psName
    if ($existing) {
        if ($Mode -eq "Deploy") {
            $ok = Delete-ErpDoc "Property Setter" $psName
            if ($ok) { Write-Host "  DELETED" -ForegroundColor Green }
            else { Write-Host "  FAILED to delete" -ForegroundColor Red }
        } else {
            Write-Host "  WOULD DELETE" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Already gone." -ForegroundColor DarkGray
    }
}

# Step 25b: Update field_order property setter to remove deleted fields
Write-Host "`n[E25b] Update field_order property setter..." -ForegroundColor White
$fieldOrderPS = Get-ErpDoc "Property Setter" "Task-main-field_order"
if ($fieldOrderPS) {
    $currentOrder = $fieldOrderPS.value
    $removedFields = @("custom_is_team_queue_task", "custom_team_queue_role", "custom_team_queue_status", "custom_team_notified")
    $newOrder = $currentOrder
    foreach ($rf in $removedFields) {
        $newOrder = $newOrder -replace ", `"$rf`"", ""
        $newOrder = $newOrder -replace "`"$rf`", ", ""
        $newOrder = $newOrder -replace "`"$rf`"", ""
    }
    if ($newOrder -ne $currentOrder) {
        if ($Mode -eq "Deploy") {
            $body = @{ value = $newOrder }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter/$(Enc 'Task-main-field_order')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Updated field_order (removed 4 fields)" -ForegroundColor Green
        } else {
            Write-Host "  WOULD UPDATE field_order (remove 4 fields)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No changes needed." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Property setter not found." -ForegroundColor DarkGray
}

# ============================================================================
# PHASE F: Telegram Notification User DocType deletion
# ============================================================================
Write-Host "`n--- Phase F: Remove Telegram Notification User DocType ---" -ForegroundColor Magenta

Write-Host "`n[F14] Telegram Notification User DocType" -ForegroundColor White
# First check if any records exist
try {
    $tnuUrl = "$BaseUrl/api/resource/Telegram%20Notification%20User?limit_page_length=5"
    $tnuRecords = (Invoke-RestMethod -Uri $tnuUrl -Headers $Headers -Method Get -TimeoutSec 30).data
} catch { $tnuRecords = @() }
if ($tnuRecords -and $tnuRecords.Count -gt 0) {
    Write-Host "  WARNING: $($tnuRecords.Count) record(s) exist. Deleting records first..." -ForegroundColor DarkYellow
    if ($Mode -eq "Deploy") {
        foreach ($rec in $tnuRecords) {
            Delete-ErpDoc "Telegram Notification User" $rec.name | Out-Null
        }
        Write-Host "  Records deleted." -ForegroundColor Green
    } else {
        Write-Host "  WOULD DELETE $($tnuRecords.Count) records" -ForegroundColor Yellow
    }
}

# Check if the DocType exists
$tnuDocType = Get-ErpDoc "DocType" "Telegram Notification User"
if ($tnuDocType) {
    if ($Mode -eq "Deploy") {
        # Delete the DocType (custom DocType can be deleted via API)
        $ok = Delete-ErpDoc "DocType" "Telegram Notification User"
        if ($ok) { Write-Host "  DELETED DocType" -ForegroundColor Green }
        else { Write-Host "  FAILED to delete DocType (may need bench console)" -ForegroundColor Red }
    } else {
        Write-Host "  WOULD DELETE DocType" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Already gone." -ForegroundColor DarkGray
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($Mode -eq "Check") {
    Write-Host "DRY RUN - no changes applied. Re-run with -Mode Deploy to apply." -ForegroundColor Yellow
} else {
    Write-Host "All changes deployed to $BaseUrl" -ForegroundColor Green
    Write-Host "`nRemaining manual steps:" -ForegroundColor White
    Write-Host "  1. Clear cache on test: docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  2. Run export to verify: powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1" -ForegroundColor DarkGray
    Write-Host "  3. Test the workflows manually on test.erpnext.am" -ForegroundColor DarkGray
}
