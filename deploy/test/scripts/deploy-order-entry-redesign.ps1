#Requires -Version 5.1
# ============================================================================
# Deploy — Phase 1: Order Entry Redesign + Downstream Script Hardening
# Target: TEST only (test.erpnext.am)
#
# ATOMIC DEPLOYMENT: All steps must be deployed together. Deploying partial
# changes (e.g. removing discount detection without the new completion gate)
# allows discounted orders to bypass approval.
#
# Steps:
#   1. Add 4 custom fields on Task (order_return_expected, order_client_location_warehouse,
#      order_surgery_date, order_template)
#   2. Update dispatch_task_accept.py (auto-create DC for Order Entry)
#   3. Update Task-before-save-dispatch-gates.py (field sync + completion gate)
#   4. Update Dispatch-Case-before-save.py (remove discount detection)
#   5. Update Task-after-save-dispatch-flow.py (Pack guard + Discount Approval submit)
#   6. Create task_apply_template.py (new API)
#   7. Update task_mark_items_packed_batch.py (ignore_validate_update_after_submit)
#   8. Update task_mark_item_packed.py (ignore_validate_update_after_submit)
#   9. Update task_update_return_item_quantities.py (ignore_validate_update_after_submit)
#  10. Update Task-after-save-advance-payment.py (ignore_validate_update_after_submit)
#  11. Update Task-Action Buttons.js (View DC link, discount confirm, Order entry in product kinds)
#  12. Update Task-Product Work Area.js (Order entry renderer)
#  13. Clear cache
# ============================================================================
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# --- Credentials (from ../export.ps1) ---
$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Get-ErpDoc([string]$DocType, [string]$Name) {
    try {
        return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data
    } catch { return $null }
}

function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

function Post-ErpDoc([string]$DocType, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60).data
}

# Read a work file and strip the metadata header (# Name:...# ---)
function Read-ServerScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    $lines = $Content -split "`n"
    $startIdx = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "# ---") { $startIdx = $i + 1; break }
    }
    return ($lines[$startIdx..($lines.Count - 1)] -join "`n").TrimStart("`n").TrimStart("`r`n")
}

# Read a client script and strip header (// Name:...// ---)
function Read-ClientScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host ""
Write-Host "=== Phase 1: Order Entry Redesign + Downstream Hardening ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Step 1: Custom Fields on Task
# ============================================================================
Write-Host "[1] Custom Fields on Task" -ForegroundColor Magenta

$CustomFields = @(
    @{
        name = "Task-order_return_expected"
        dt = "Task"
        fieldname = "order_return_expected"
        label = "Return Expected"
        fieldtype = "Check"
        insert_after = "dispatch_case_status"
        hidden = 1
        read_only = 0
        reqd = 0
        default_value = "0"
        description = "Order Entry: whether return is expected after delivery"
    },
    @{
        name = "Task-order_client_location_warehouse"
        dt = "Task"
        fieldname = "order_client_location_warehouse"
        label = "Client Location Warehouse"
        fieldtype = "Link"
        options = "Warehouse"
        insert_after = "order_return_expected"
        hidden = 1
        read_only = 0
        reqd = 0
        description = "Order Entry: client location warehouse (required when return expected)"
    },
    @{
        name = "Task-order_surgery_date"
        dt = "Task"
        fieldname = "order_surgery_date"
        label = "Surgery Date"
        fieldtype = "Date"
        insert_after = "order_client_location_warehouse"
        hidden = 1
        read_only = 0
        reqd = 0
        description = "Order Entry: surgery date"
    },
    @{
        name = "Task-order_template"
        dt = "Task"
        fieldname = "order_template"
        label = "Surgical Kit Template"
        fieldtype = "Link"
        options = "Surgical Kit Template"
        insert_after = "order_surgery_date"
        hidden = 1
        read_only = 0
        reqd = 0
        description = "Order Entry: select a surgical kit template to auto-fill items"
    }
)

foreach ($cf in $CustomFields) {
    $existing = Get-ErpDoc "Custom Field" $cf.name
    if ($Mode -eq "Check") {
        if ($existing) {
            Write-Host "  EXISTS: $($cf.name)" -ForegroundColor DarkGray
        } else {
            Write-Host "  WOULD CREATE: $($cf.name)" -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Put-ErpDoc "Custom Field" $cf.name $cf | Out-Null
            Write-Host "  UPDATED: $($cf.name)" -ForegroundColor Green
        } else {
            $cfBody = $cf.Clone()
            $cfBody["doctype"] = "Custom Field"
            Post-ErpDoc "Custom Field" $cfBody | Out-Null
            Write-Host "  CREATED: $($cf.name)" -ForegroundColor Green
        }
    }
}

# ============================================================================
# Steps 2-6: Server Scripts (update existing + create new)
# ============================================================================
Write-Host "`n[2-6] Server Scripts" -ForegroundColor Magenta

$ServerScripts = @(
    @{ name = "dispatch_task_accept"; file = "server\dispatch_task_accept.py"; type = "API"; doctype = ""; event = "" },
    @{ name = "Task-before-save-dispatch-gates"; file = "server\Task-before-save-dispatch-gates.py"; type = "DocType Event"; doctype = "Task"; event = "Before Save" },
    @{ name = "Dispatch-Case-before-save"; file = "server\Dispatch-Case-before-save.py"; type = "DocType Event"; doctype = "Dispatch Case"; event = "Before Save" },
    @{ name = "Task-after-save-dispatch-flow"; file = "server\Task-after-save-dispatch-flow.py"; type = "DocType Event"; doctype = "Task"; event = "After Save" }
)

foreach ($ss in $ServerScripts) {
    $scriptPath = Join-Path $WorkDir $ss.file
    $scriptBody = Read-ServerScript $scriptPath
    $existing = Get-ErpDoc "Server Script" $ss.name

    if ($Mode -eq "Check") {
        if ($existing) {
            $currentLen = ([string]$existing.script).Length
            $newLen = $scriptBody.Length
            Write-Host "  $($ss.name): current=$currentLen chars, new=$newLen chars" -ForegroundColor DarkGray
        } else {
            Write-Host "  $($ss.name): NOT FOUND (unexpected)" -ForegroundColor Red
        }
    } else {
        if (-not $existing) { throw "Server Script '$($ss.name)' not found on server" }
        $body = @{ script = $scriptBody; disabled = 0 }
        if ($ss.type -eq "DocType Event") {
            $body.reference_doctype = $ss.doctype
            $body.doctype_event = $ss.event
        }
        $json = $body | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $ss.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
        Write-Host "  UPDATED: $($ss.name)" -ForegroundColor Green
    }
}

# New API script: task_apply_template
Write-Host "`n[6] task_apply_template (CREATE/UPDATE)" -ForegroundColor Magenta
$templatePath = Join-Path $WorkDir "server\task_apply_template.py"
$templateBody = Read-ServerScript $templatePath
$existingTemplate = Get-ErpDoc "Server Script" "task_apply_template"

if ($Mode -eq "Check") {
    if ($existingTemplate) {
        Write-Host "  task_apply_template: EXISTS (will update)" -ForegroundColor DarkGray
    } else {
        Write-Host "  task_apply_template: WOULD CREATE" -ForegroundColor Yellow
    }
} else {
    if ($existingTemplate) {
        Put-ErpDoc "Server Script" "task_apply_template" @{ script = $templateBody; disabled = 0 } | Out-Null
        Write-Host "  UPDATED: task_apply_template" -ForegroundColor Green
    } else {
        Post-ErpDoc "Server Script" @{
            doctype = "Server Script"
            name = "task_apply_template"
            script_type = "API"
            api_method = "task_apply_template"
            script = $templateBody
            disabled = 0
        } | Out-Null
        Write-Host "  CREATED: task_apply_template" -ForegroundColor Green
    }
}

# ============================================================================
# Steps 7-10: Downstream script hardening (ignore_validate_update_after_submit)
# ============================================================================
Write-Host "`n[7-10] Downstream Script Hardening" -ForegroundColor Magenta

$HardenScripts = @(
    @{ name = "task_mark_items_packed_batch"; file = "server\task_mark_items_packed_batch.py"; type = "API"; doctype = ""; event = "" },
    @{ name = "task_mark_item_packed"; file = "server\task_mark_item_packed.py"; type = "API"; doctype = ""; event = "" },
    @{ name = "task_update_return_item_quantities"; file = "server\task_update_return_item_quantities.py"; type = "API"; doctype = ""; event = "" },
    @{ name = "Task-after-save-advance-payment"; file = "server\Task-after-save-advance-payment.py"; type = "DocType Event"; doctype = "Task"; event = "After Save" }
)

foreach ($ss in $HardenScripts) {
    $scriptPath = Join-Path $WorkDir $ss.file
    $scriptBody = Read-ServerScript $scriptPath
    $existing = Get-ErpDoc "Server Script" $ss.name

    $hasFlag = $scriptBody -match "ignore_validate_update_after_submit"
    if ($Mode -eq "Check") {
        if ($existing) {
            $liveHasFlag = ([string]$existing.script) -match "ignore_validate_update_after_submit"
            Write-Host "  $($ss.name): live_has_flag=$liveHasFlag, new_has_flag=$hasFlag" -ForegroundColor $(if ($hasFlag) { "Green" } else { "Red" })
        } else {
            Write-Host "  $($ss.name): NOT FOUND" -ForegroundColor Red
        }
    } else {
        if (-not $existing) { throw "Server Script '$($ss.name)' not found on server" }
        $body = @{ script = $scriptBody; disabled = 0 }
        if ($ss.type -eq "DocType Event") {
            $body.reference_doctype = $ss.doctype
            $body.doctype_event = $ss.event
        }
        $json = $body | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $ss.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
        Write-Host "  UPDATED: $($ss.name)" -ForegroundColor Green
    }
}

# ============================================================================
# Steps 11-12: Client Scripts
# ============================================================================
Write-Host "`n[11-12] Client Scripts" -ForegroundColor Magenta

$ClientScripts = @(
    @{ name = "Task-Action Buttons"; file = "client\Task-Action Buttons.js" },
    @{ name = "Task-Product Work Area"; file = "client\Task-Product Work Area.js" }
)

foreach ($cs in $ClientScripts) {
    $scriptPath = Join-Path $WorkDir $cs.file
    $scriptBody = Read-ClientScript $scriptPath
    $existing = Get-ErpDoc "Client Script" $cs.name

    if ($Mode -eq "Check") {
        if ($existing) {
            $currentLen = ([string]$existing.script).Length
            $newLen = $scriptBody.Length
            Write-Host "  $($cs.name): current=$currentLen chars, new=$newLen chars" -ForegroundColor DarkGray
        } else {
            Write-Host "  $($cs.name): NOT FOUND (unexpected)" -ForegroundColor Red
        }
    } else {
        if (-not $existing) { throw "Client Script '$($cs.name)' not found on server" }
        Put-ErpDoc "Client Script" $cs.name @{
            script = $scriptBody
            enabled = 1
        } | Out-Null
        Write-Host "  UPDATED: $($cs.name)" -ForegroundColor Green
    }
}

# ============================================================================
# Step 13: Clear cache
# ============================================================================
Write-Host "`n[13] Clear Cache" -ForegroundColor Magenta
if ($Mode -eq "Deploy") {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 30 | Out-Null
        Write-Host "  Cache cleared via API" -ForegroundColor Green
    } catch {
        Write-Host "  API cache clear failed (non-critical): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "`n  IMPORTANT: Also run:" -ForegroundColor Yellow
    Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor White
} else {
    Write-Host "  WOULD clear cache" -ForegroundColor Yellow
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "After deploying, hard refresh ERPNext (Ctrl+Shift+R) and test:" -ForegroundColor White
Write-Host "  1. Accept Order Entry task -> DC auto-created" -ForegroundColor White
Write-Host "  2. Add items via Product Work Area" -ForegroundColor White
Write-Host "  3. Complete no-discount order -> DC submitted, Pack created" -ForegroundColor White
Write-Host "  4. Complete discounted order -> Confirm dialog -> Awaiting Approval" -ForegroundColor White
Write-Host "  5. Existing Pack/Delivery/Returns/Invoice flows unchanged" -ForegroundColor White
