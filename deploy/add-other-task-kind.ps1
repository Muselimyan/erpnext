#Requires -Version 5.1
<#
.SYNOPSIS
    Add "Other" task kind to ERPNext Task system.
    Creates custom fields for Other task kind: checkboxes child table, budget, supplier.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — create / update all artefacts (idempotent)
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action="created"; name=$C.name }
    }
    $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$U.name }
}

Write-Host "=== Add 'Other' Task Kind ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# 1) CREATE CHILD DOCTYPE: Task Other Item (for checkboxes)
# ---------------------------------------------------------------------------
$TaskOtherItemDocType = @{
    doctype = "DocType"
    name = "Task Other Item"
    module = "Projects"
    custom = 1
    istable = 1
    editable_grid = 1
    fields = @(
        @{ fieldname="description"; label="Description"; fieldtype="Data"; in_list_view=1; reqd=1 },
        @{ fieldname="is_completed"; label="Completed"; fieldtype="Check"; in_list_view=1 }
    )
    permissions = @(
        @{ role="All"; read=1; write=1; create=1 }
    )
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "DocType" -Name "Task Other Item"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Task Other Item DocType (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Task Other Item DocType exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Task Other Item DocType..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "DocType" -Name "Task Other Item" -Body $TaskOtherItemDocType
    Write-Host "  [✓] Task Other Item DocType $($Result.action)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2) ADD CUSTOM FIELDS TO TASK
# ---------------------------------------------------------------------------
$CustomFields = @(
    @{
        name = "Task-other_items"
        dt = "Task"
        fieldname = "other_items"
        label = "Other Task Items"
        fieldtype = "Table"
        options = "Task Other Item"
        depends_on = "eval:doc.task_kind=='Other'"
    },
    @{
        name = "Task-other_budget"
        dt = "Task"
        fieldname = "other_budget"
        label = "Budget / Amount"
        fieldtype = "Currency"
        depends_on = "eval:doc.task_kind=='Other'"
    },
    @{
        name = "Task-other_supplier"
        dt = "Task"
        fieldname = "other_supplier"
        label = "Supplier"
        fieldtype = "Link"
        options = "Supplier"
        depends_on = "eval:doc.task_kind=='Other'"
    }
)

foreach ($Field in $CustomFields) {
    if ($Mode -eq "Check") {
        $Existing = Get-ErpDoc -DocType "Custom Field" -Name $Field.name
        if ($null -eq $Existing) {
            Write-Host "  [ ] Custom Field: $($Field.name) (will be created)" -ForegroundColor Yellow
        } else {
            Write-Host "  [✓] Custom Field: $($Field.name) exists" -ForegroundColor Green
        }
    } else {
        Write-Host "  Creating/updating Custom Field: $($Field.name)..." -ForegroundColor Cyan
        $Body = @{
            doctype = "Custom Field"
            dt = $Field.dt
            fieldname = $Field.fieldname
            label = $Field.label
            fieldtype = $Field.fieldtype
        }
        if ($Field.options) { $Body.options = $Field.options }
        if ($Field.depends_on) { $Body.depends_on = $Field.depends_on }
        
        $Result = Upsert-ErpDoc -DocType "Custom Field" -Name $Field.name -Body $Body
        Write-Host "  [✓] Custom Field: $($Field.name) $($Result.action)" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# 3) UPDATE TASK KIND OPTIONS (add "Other")
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== UPDATE TASK KIND OPTIONS ===" -ForegroundColor Cyan
Write-Host "You need to manually update the Task-task_kind Custom Field to add 'Other' to the options." -ForegroundColor Yellow
Write-Host "Run this command in ERPNext console or update doc16a-deploy.ps1:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Add 'Other' to the TaskKindOptions list in doc16a-deploy.ps1, then re-run:" -ForegroundColor White
Write-Host "  .\deploy\doc16a-deploy.ps1 -Mode Deploy" -ForegroundColor Cyan
Write-Host ""
Write-Host "OR manually in ERPNext:" -ForegroundColor White
Write-Host "  1. Search for 'Custom Field'" -ForegroundColor White
Write-Host "  2. Find 'Task-task_kind'" -ForegroundColor White
Write-Host "  3. Add 'Other' to the Options field" -ForegroundColor White
Write-Host "  4. Save" -ForegroundColor White
Write-Host ""

# ---------------------------------------------------------------------------
# 4) CREATE TASK ACCESS POLICY FOR "OTHER"
# ---------------------------------------------------------------------------
$TaskAccessPolicy = @{
    doctype = "Task Access Policy"
    name = "Other"
    policy_name = "Other"
    allowed_roles = @(
        @{ role = "Ops - Order Accepting" },
        @{ role = "Ops - Order Creating" },
        @{ role = "Ops - Inventory" },
        @{ role = "Ops - Returns" },
        @{ role = "Ops - Delivery" },
        @{ role = "Ops - Accounting" },
        @{ role = "Ops - Directors" },
        @{ role = "Ops - Finance" },
        @{ role = "Delivery Driver" }
    )
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "Task Access Policy" -Name "Other"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Task Access Policy: Other (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Task Access Policy: Other exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Task Access Policy: Other..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "Task Access Policy" -Name "Other" -Body $TaskAccessPolicy
    Write-Host "  [✓] Task Access Policy: Other $($Result.action)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Green
if ($Mode -eq "Check") {
    Write-Host "Run with -Mode Deploy to create/update artifacts" -ForegroundColor Yellow
} else {
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "1. Update doc16a-deploy.ps1 to add 'Other' to TaskKindOptions" -ForegroundColor White
    Write-Host "2. Run: .\deploy\doc16a-deploy.ps1 -Mode Deploy" -ForegroundColor White
    Write-Host "3. Test creating a task with kind 'Other'" -ForegroundColor White
}
