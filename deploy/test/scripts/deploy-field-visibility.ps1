#Requires -Version 5.1
# ============================================================================
# Deploy — Task Field Visibility (TFV) Phase 0+1
# Target: TEST only (test.erpnext.am)
#
# Phase 0: Creates Task-Field-Visibility.js (centralized visibility script).
# Phase 1: Sets all Task custom fields to hidden=1, clears depends_on
#           expressions, adds status/priority hidden property setters,
#           and cleans ghost fields from field_order.
#
# Run with -Mode Check first to preview changes.
# Run with -Mode Deploy to apply.
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
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# --- REST helpers ---
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

function Get-ErpList([string]$DocType, [string]$Filters, [string]$Fields = '["name"]', [int]$Limit = 100) {
    $uri = "$BaseUrl/api/resource/$(Enc $DocType)?filters=$(Enc $Filters)&fields=$(Enc $Fields)&limit_page_length=$Limit"
    try {
        $result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get -TimeoutSec 30
        return $result.data
    } catch { return @() }
}

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work\client"

Write-Host "`n=== Task Field Visibility -- Phase 0+1 ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: CREATE/UPDATE Task-Field-Visibility client script
# ============================================================================
Write-Host "[1] Task-Field-Visibility client script" -ForegroundColor Magenta
$tfvFile = Join-Path $WorkDir "Task-Field-Visibility.js"
if (-not (Test-Path $tfvFile)) { throw "TFV script not found: $tfvFile" }
$tfvScript = Read-WorkScript $tfvFile
$existingTFV = Get-ErpDoc "Client Script" "Task-Field-Visibility"

if ($Mode -eq "Check") {
    if ($existingTFV) {
        $currentLen = ([string]$existingTFV.script).Length
        Write-Host "  EXISTS (enabled=$($existingTFV.enabled), $currentLen chars)" -ForegroundColor DarkGray
        Write-Host "  New script: $($tfvScript.Length) chars" -ForegroundColor DarkGray
    } else {
        Write-Host "  WOULD CREATE ($($tfvScript.Length) chars)" -ForegroundColor Yellow
    }
} else {
    if ($existingTFV) {
        Put-ErpDoc "Client Script" "Task-Field-Visibility" @{
            script  = $tfvScript
            enabled = 1
        } | Out-Null
        Write-Host "  UPDATED" -ForegroundColor Green
    } else {
        Post-ErpDoc "Client Script" @{
            name    = "Task-Field-Visibility"
            dt      = "Task"
            view    = "Form"
            script  = $tfvScript
            enabled = 1
        } | Out-Null
        Write-Host "  CREATED" -ForegroundColor Green
    }
}

# ============================================================================
# Step 2: Set hidden=1 and clear depends_on on all Task custom fields
# ============================================================================
Write-Host "`n[2] Custom Fields: hidden=1, depends_on=''" -ForegroundColor Magenta

# All 52 Task custom fields (in schema order)
$allTaskFields = @(
    "task_kind", "completed_at", "task_access_policy",
    "purchase_order", "approval_outcome", "approval_note",
    "customer", "payment_entry", "current_debt_amd", "debt_threshold_amd",
    "dispatch_group_id", "sales_invoice", "driver_handover_note",
    "delivery_status", "pickup_status",
    "return_pickup_driver", "scheduled_return_date",
    "new_payment_amount", "payment_method_dc", "payment_reference_dc",
    "total_outstanding", "available_advance_credit",
    "dispatch_case", "open_invoices", "payment_history",
    "custom_accepted_by", "custom_accepted_at",
    "custom_product_work_section", "custom_task_product_summary",
    "custom_task_scan_barcode", "custom_task_scan_qty", "custom_task_scan_result",
    "custom_task_product_warning",
    "custom_task_add_item_code", "custom_task_add_qty",
    "custom_task_add_batch_no", "custom_task_add_unit_price",
    # custom_barcode_section deleted (fields moved into product_work_section)
    # custom_product_lines deleted (Phase 9)
    "dispatch_case_status",
    "other_items", "other_budget", "other_supplier",
    "custom_case_profit", "custom_total_amount_paid",
    "custom_account_details_section", "custom_account_photos",
    "custom_assigned_to", "custom_next_task_assign_to",
    "custom_account_details_entry_task", "custom_account_details_subject"
)

# Column Break: do NOT set hidden=1 (inherits from parent section)
$columnBreak = "custom_product_work_column"

$changed = 0; $skipped = 0; $alreadyOk = 0
foreach ($fn in $allTaskFields) {
    $cfName = "Task-$fn"
    $existing = Get-ErpDoc "Custom Field" $cfName
    if (-not $existing) {
        Write-Host "  SKIP (not found): $fn" -ForegroundColor DarkYellow
        $skipped++
        continue
    }
    $needsHidden  = ([int]$existing.hidden) -ne 1
    $currentDep   = if ($existing.depends_on) { $existing.depends_on } else { "" }
    $needsDepends = ($currentDep -ne "")

    if (-not $needsHidden -and -not $needsDepends) {
        $alreadyOk++
        continue
    }

    if ($Mode -eq "Check") {
        $parts = @()
        if ($needsHidden)  { $parts += "hidden 0->1" }
        if ($needsDepends) { $parts += "depends_on: CLEAR" }
        Write-Host "  $fn : $($parts -join ', ')" -ForegroundColor Yellow
        $changed++
    } else {
        $body = @{ hidden = 1 }
        if ($needsDepends) { $body["depends_on"] = "" }
        Put-ErpDoc "Custom Field" $cfName $body | Out-Null
        Write-Host "  OK: $fn" -ForegroundColor Green
        $changed++
    }
}

# Handle Column Break separately (depends_on only, keep hidden=0)
$cbDoc = Get-ErpDoc "Custom Field" "Task-$columnBreak"
if ($cbDoc) {
    $cbDep = if ($cbDoc.depends_on) { $cbDoc.depends_on } else { "" }
    if ($cbDep -ne "") {
        if ($Mode -eq "Check") {
            Write-Host "  $columnBreak (Col Break): depends_on CLEAR (hidden stays 0)" -ForegroundColor Yellow
        } else {
            Put-ErpDoc "Custom Field" "Task-$columnBreak" @{ depends_on = "" } | Out-Null
            Write-Host "  OK: $columnBreak (depends_on only)" -ForegroundColor Green
        }
    } else {
        Write-Host "  $columnBreak (Col Break): already clean" -ForegroundColor DarkGray
    }
}

Write-Host "  --- $changed to change, $alreadyOk already ok, $skipped not found ---" -ForegroundColor $(if ($changed -gt 0) { "Yellow" } else { "Green" })

# ============================================================================
# Step 3: Clear all depends_on Property Setters for Task
# ============================================================================
Write-Host "`n[3] Property Setters: clear depends_on" -ForegroundColor Magenta

$psData = Get-ErpList "Property Setter" '[["doc_type","=","Task"],["property","=","depends_on"]]' '["name","field_name","value"]' 200

$psTotal = ($psData | Measure-Object).Count
$psToClear = 0

if ($Mode -eq "Check") {
    Write-Host "  Found $psTotal depends_on property setters" -ForegroundColor DarkGray
    foreach ($ps in $psData) {
        if ($ps.value -and $ps.value -ne "") {
            Write-Host "    $($ps.field_name): WOULD CLEAR" -ForegroundColor Yellow
            $psToClear++
        }
    }
    Write-Host "  --- $psToClear to clear ---" -ForegroundColor $(if ($psToClear -gt 0) { "Yellow" } else { "Green" })
} else {
    foreach ($ps in $psData) {
        if ($ps.value -and $ps.value -ne "") {
            Put-ErpDoc "Property Setter" $ps.name @{ value = "" } | Out-Null
            Write-Host "  CLEARED: $($ps.field_name)" -ForegroundColor Green
            $psToClear++
        }
    }
    Write-Host "  --- Cleared $psToClear / $psTotal ---" -ForegroundColor Green
}

# ============================================================================
# Step 4: Add hidden=1 Property Setters for status and priority
# ============================================================================
Write-Host "`n[4] Property Setters: hidden=1 for status, priority" -ForegroundColor Magenta

foreach ($stdField in @("status", "priority")) {
    $psFilter = '[["doc_type","=","Task"],["field_name","=","' + $stdField + '"],["property","=","hidden"]]'
    $psHidden = Get-ErpList "Property Setter" $psFilter '["name","value"]'
    $found = ($psHidden | Measure-Object).Count

    if ($Mode -eq "Check") {
        if ($found -gt 0) {
            Write-Host "  $stdField : hidden already set (value=$($psHidden[0].value))" -ForegroundColor DarkGray
        } else {
            Write-Host "  $stdField : WOULD CREATE hidden=1" -ForegroundColor Yellow
        }
    } else {
        if ($found -gt 0) {
            if ($psHidden[0].value -ne "1") {
                Put-ErpDoc "Property Setter" $psHidden[0].name @{ value = "1" } | Out-Null
                Write-Host "  UPDATED: $stdField hidden=1" -ForegroundColor Green
            } else {
                Write-Host "  $stdField : already hidden=1" -ForegroundColor DarkGray
            }
        } else {
            Post-ErpDoc "Property Setter" @{
                doctype_or_field = "DocField"
                doc_type         = "Task"
                field_name       = $stdField
                property         = "hidden"
                value            = "1"
            } | Out-Null
            Write-Host "  CREATED: $stdField hidden=1" -ForegroundColor Green
        }
    }
}

# ============================================================================
# Step 5: Clean field_order -- remove ghost fields
# ============================================================================
Write-Host "`n[5] Field order: remove ghost fields" -ForegroundColor Magenta

$ghostFields = @(
    "warehouse_pickup_photo",
    "custom_delivery_photo",
    "warehouse_dropoff_photo",
    "surgery_case",
    "custom_select_surgical_kit_template"
)

$foData = Get-ErpList "Property Setter" '[["doc_type","=","Task"],["property","=","field_order"]]' '["name","value"]'
$foCount = ($foData | Measure-Object).Count

if ($foCount -gt 0) {
    $foName = $foData[0].name
    $currentOrder = $foData[0].value | ConvertFrom-Json
    $ghostsFound = @($ghostFields | Where-Object { $currentOrder -contains $_ })

    if ($Mode -eq "Check") {
        Write-Host "  Current field_order: $($currentOrder.Count) entries" -ForegroundColor DarkGray
        if ($ghostsFound.Count -gt 0) {
            Write-Host "  Ghost fields: $($ghostsFound -join ', ')" -ForegroundColor Yellow
            Write-Host "  WOULD REMOVE $($ghostsFound.Count) ghost(s)" -ForegroundColor Yellow
        } else {
            Write-Host "  No ghosts found" -ForegroundColor Green
        }
    } else {
        if ($ghostsFound.Count -gt 0) {
            $newOrder = @($currentOrder | Where-Object { $ghostFields -notcontains $_ })
            $newOrderJson = ConvertTo-Json $newOrder -Compress
            Put-ErpDoc "Property Setter" $foName @{ value = $newOrderJson } | Out-Null
            Write-Host "  REMOVED $($ghostsFound.Count) ghost(s): $($ghostsFound -join ', ')" -ForegroundColor Green
            Write-Host "  New field_order: $($newOrder.Count) entries" -ForegroundColor Green
        } else {
            Write-Host "  No ghosts to remove" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  field_order property setter NOT FOUND" -ForegroundColor Red
}

# ============================================================================
# Step 6: Clear cache
# ============================================================================
Write-Host "`n[6] Post-deploy" -ForegroundColor Magenta
if ($Mode -eq "Deploy") {
    Write-Host "  Run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
    Write-Host "  Then: powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1" -ForegroundColor Yellow
} else {
    Write-Host "  (skipped in Check mode)" -ForegroundColor DarkGray
}

Write-Host "`n=== Done ($Mode mode) ===" -ForegroundColor Cyan
