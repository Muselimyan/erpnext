#Requires -Version 5.1
# ============================================================================
# Deploy — Unify Team Mappings + Add Diagnostic Logging
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

Write-Host "`n=== Unify Team Mappings + Diagnostic Logging ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode: $Mode`n" -ForegroundColor Yellow

# ============================================================================
# PHASE A: Create child DocType "Task Access Policy Role"
# ============================================================================
Write-Host "--- Phase A: Child DocType ---" -ForegroundColor Magenta

Write-Host "`n[A1] Child DocType: Task Access Policy Role..." -ForegroundColor White
$childDT = Get-ErpDoc "DocType" "Task Access Policy Role"
if ($childDT) {
    Write-Host "  Already exists." -ForegroundColor DarkGray
} else {
    if ($Mode -eq "Deploy") {
        $childBody = @{
            name = "Task Access Policy Role"
            doctype = "DocType"
            module = "Custom"
            custom = 1
            istable = 1
            editable_grid = 1
            fields = @(
                @{
                    fieldname = "role"
                    fieldtype = "Link"
                    label = "Role"
                    options = "Role"
                    in_list_view = 1
                    reqd = 1
                }
            )
        }
        $json = $childBody | ConvertTo-Json -Depth 40 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/DocType" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  CREATED: Task Access Policy Role" -ForegroundColor Green
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  WOULD CREATE: Task Access Policy Role (istable=1, field: role Link->Role)" -ForegroundColor Yellow
    }
}

# ============================================================================
# PHASE B: Add fields to Task Access Policy
# ============================================================================
Write-Host "`n--- Phase B: Add Fields to Task Access Policy ---" -ForegroundColor Magenta

Write-Host "`n[B1] Custom Field: Task Access Policy-default_team_user..." -ForegroundColor White
$dtField = Get-ErpDoc "Custom Field" "Task Access Policy-default_team_user"
if ($dtField) {
    Write-Host "  Already exists." -ForegroundColor DarkGray
} else {
    if ($Mode -eq "Deploy") {
        $fieldBody = [ordered]@{
            dt = "Task Access Policy"
            fieldname = "default_team_user"
            label = "Default Team User"
            fieldtype = "Link"
            options = "User"
            insert_after = "policy_name"
        }
        $r = Upsert-ErpDoc "Custom Field" "Task Access Policy-default_team_user" $fieldBody
        Write-Host "  $($r.action): Task Access Policy-default_team_user" -ForegroundColor Green
    } else {
        Write-Host "  WOULD CREATE: Task Access Policy-default_team_user (Link->User)" -ForegroundColor Yellow
    }
}

Write-Host "`n[B2] Custom Field: Task Access Policy-allowed_roles..." -ForegroundColor White
$arField = Get-ErpDoc "Custom Field" "Task Access Policy-allowed_roles"
if ($arField) {
    Write-Host "  Already exists." -ForegroundColor DarkGray
} else {
    if ($Mode -eq "Deploy") {
        $fieldBody = [ordered]@{
            dt = "Task Access Policy"
            fieldname = "allowed_roles"
            label = "Allowed Roles"
            fieldtype = "Table"
            options = "Task Access Policy Role"
            insert_after = "default_team_user"
        }
        $r = Upsert-ErpDoc "Custom Field" "Task Access Policy-allowed_roles" $fieldBody
        Write-Host "  $($r.action): Task Access Policy-allowed_roles" -ForegroundColor Green
    } else {
        Write-Host "  WOULD CREATE: Task Access Policy-allowed_roles (Table->Task Access Policy Role)" -ForegroundColor Yellow
    }
}

# ============================================================================
# PHASE C: Create missing policy records + populate all
# ============================================================================
Write-Host "`n--- Phase C: Populate Task Access Policy Records ---" -ForegroundColor Magenta

# Define the canonical data
$PolicyData = @(
    @{ name = "Order entry"; team = "order.creation.team@example.com"; roles = @("Ops - Order Accepting", "Ops - Order Creating") },
    @{ name = "Pack / prepare items"; team = "inventory.team@example.com"; roles = @("Ops - Inventory") },
    @{ name = "Dispatch picking / hand-off"; team = "delivery.team@example.com"; roles = @("Ops - Delivery") },
    @{ name = "Delivery"; team = "delivery.team@example.com"; roles = @("Delivery Driver", "Ops - Delivery") },
    @{ name = "Return Call"; team = "office.team@example.com"; roles = @("Ops - Returns", "Ops - Order Accepting") },
    @{ name = "Return to warehouse (aborted delivery / cancelled order)"; team = "delivery.team@example.com"; roles = @("Delivery Driver", "Ops - Delivery") },
    @{ name = "Pickup Returns"; team = "delivery.team@example.com"; roles = @("Delivery Driver", "Ops - Delivery", "Ops - Returns") },
    @{ name = "Return drop-off at warehouse"; team = "delivery.team@example.com"; roles = @("Delivery Driver", "Ops - Delivery") },
    @{ name = "Returns processing / verification"; team = "returns.team@example.com"; roles = @("Ops - Returns", "Ops - Inventory") },
    @{ name = "Returns restocking"; team = "returns.team@example.com"; roles = @("Ops - Returns") },
    @{ name = "Invoice preparation / create invoice"; team = "accounting.team@example.com"; roles = @("Ops - Accounting") },
    @{ name = "Debt Collection"; team = "finance.team@example.com"; roles = @("Ops - Finance", "Ops - Directors") },
    @{ name = "Distribute Payment"; team = "finance.team@example.com"; roles = @("Ops - Finance", "Ops - Directors") },
    @{ name = "Payment Received"; team = "finance.team@example.com"; roles = @("Ops - Finance", "Ops - Directors") },
    @{ name = "Discount Approval"; team = "directors.team@example.com"; roles = @("Ops - Directors") },
    @{ name = "Purchase Approval"; team = "directors.team@example.com"; roles = @("Ops - Directors") },
    @{ name = "Write-off Approval"; team = "directors.team@example.com"; roles = @("Ops - Directors") },
    @{ name = "Account Details: Entry"; team = "accounting.team@example.com"; roles = @("Ops - Accounting", "Ops - Finance", "Ops - Directors") },
    @{ name = "Account Details: Processing"; team = "accounting.team@example.com"; roles = @("Ops - Accounting", "Ops - Finance", "Ops - Directors") },
    @{ name = "Other"; team = "office.team@example.com"; roles = @("Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver") },
    @{ name = "Other: Entry"; team = "office.team@example.com"; roles = @("Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver") },
    @{ name = "Other: Processing"; team = "office.team@example.com"; roles = @("Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver") },
    @{ name = "Debt Closure Approval"; team = "directors.team@example.com"; roles = @("Ops - Directors") }
)

foreach ($pol in $PolicyData) {
    $pName = $pol.name
    Write-Host "`n[C] $pName" -ForegroundColor White

    $existing = Get-ErpDoc "Task Access Policy" $pName

    # Build the allowed_roles child table rows
    $roleRows = @()
    foreach ($roleName in $pol.roles) {
        $roleRows += @{ role = $roleName }
    }

    if ($existing) {
        # Update existing record with default_team_user and allowed_roles
        if ($Mode -eq "Deploy") {
            $body = @{
                default_team_user = $pol.team
                allowed_roles = $roleRows
            }
            $json = $body | ConvertTo-Json -Depth 40 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task%20Access%20Policy/$(Enc $pName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Updated: team=$($pol.team) roles=$($pol.roles.Count)" -ForegroundColor Green
        } else {
            Write-Host "  WOULD UPDATE: team=$($pol.team) roles=$($pol.roles.Count)" -ForegroundColor Yellow
        }
    } else {
        # Create new record
        if ($Mode -eq "Deploy") {
            $body = @{
                policy_name = $pName
                default_team_user = $pol.team
                allowed_roles = $roleRows
            }
            $json = $body | ConvertTo-Json -Depth 40 -Compress
            try {
                Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task%20Access%20Policy" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
                Write-Host "  CREATED: team=$($pol.team) roles=$($pol.roles.Count)" -ForegroundColor Green
            } catch {
                Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  WOULD CREATE: team=$($pol.team) roles=$($pol.roles.Count)" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# PHASE C2: Add Other: Entry / Other: Processing to task_kind Select options
# ============================================================================
Write-Host "`n--- Phase C2: Update task_kind Select Options ---" -ForegroundColor Magenta

Write-Host "`n[C2] task_kind custom field options..." -ForegroundColor White
$tkField = Get-ErpDoc "Custom Field" "Task-task_kind"
if ($tkField) {
    $currentOpts = $tkField.options -split "`n"
    $needsUpdate = $false
    if ("Other: Entry" -notin $currentOpts) { $needsUpdate = $true }
    if ("Other: Processing" -notin $currentOpts) { $needsUpdate = $true }
    if ($needsUpdate) {
        $newOpts = $currentOpts
        # Insert before "Debt Closure Approval" (last entry) or at end
        if ("Other: Entry" -notin $newOpts) { $insertIdx = [array]::IndexOf($newOpts, "Other") + 1; $newOpts = $newOpts[0..($insertIdx-1)] + @("Other: Entry", "Other: Processing") + $newOpts[$insertIdx..($newOpts.Count-1)] }
        $newOptsStr = $newOpts -join "`n"
        if ($Mode -eq "Deploy") {
            $body = @{ options = $newOptsStr }
            $json = $body | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc 'Task-task_kind')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
            Write-Host "  Added Other: Entry, Other: Processing to options" -ForegroundColor Green
        } else {
            Write-Host "  WOULD ADD Other: Entry, Other: Processing to options" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Already includes Other: Entry and Other: Processing" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: Task-task_kind custom field not found" -ForegroundColor Red
}

# ============================================================================
# PHASE D: Deploy server scripts
# ============================================================================
Write-Host "`n--- Phase D: Server Scripts ---" -ForegroundColor Magenta

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"
$ServerScripts = @(
    @{ name = "Task-before-save-policy"; file = "server\Task-before-save-policy.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "dispatch_task_accept"; file = "server\dispatch_task_accept.py"; doctype = ""; event = ""; type = "API"; disabled = 0 },
    @{ name = "task_list_filtered"; file = "server\task_list_filtered.py"; doctype = ""; event = ""; type = "API"; disabled = 0 },
    @{ name = "Task-before-save-lock-unaccepted"; file = "server\Task-before-save-lock-unaccepted.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-before-save-dispatch-gates"; file = "server\Task-before-save-dispatch-gates.py"; doctype = "Task"; event = "Before Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-after-save-dispatch-flow"; file = "server\Task-after-save-dispatch-flow.py"; doctype = "Task"; event = "After Save"; type = "DocType Event"; disabled = 0 },
    @{ name = "Task-after-save-other-processing"; file = "server\Task-after-save-other-processing.py"; doctype = "Task"; event = "After Save"; type = "DocType Event"; disabled = 0 },
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
# PHASE E: Deploy client scripts
# ============================================================================
Write-Host "`n--- Phase E: Client Scripts ---" -ForegroundColor Magenta

$ClientScripts = @(
    @{ name = "Task-Accept Start"; file = "client\Task-Accept Start.js"; enabled = 1 },
    @{ name = "Task-Lock Unaccepted"; file = "client\Task-Lock Unaccepted.js"; enabled = 1 },
    @{ name = "Task-Dispatch Packing Usability"; file = "client\Task-Dispatch Packing Usability.js"; enabled = 1 },
    @{ name = "Global-Mobile Back Button List"; file = "client\Global-Mobile Back Button List.js"; enabled = 1 },
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
            Write-Host "  Updated" -ForegroundColor Green
        } else {
            Write-Host "  WOULD UPDATE" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  NOT FOUND on server - script may have a different name" -ForegroundColor Red
    }
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
    Write-Host "  1. Clear cache: docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  2. Run export: powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1" -ForegroundColor DarkGray
    Write-Host "  3. Test workflows on test.erpnext.am" -ForegroundColor DarkGray
}
