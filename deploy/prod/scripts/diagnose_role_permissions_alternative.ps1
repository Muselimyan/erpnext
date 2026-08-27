param()

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) { [uri]::EscapeDataString($Value) }
function Invoke-ErpGet { param([string]$Path) Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -ErrorAction Stop }
function Invoke-ErpPost { param([string]$Path, $Body) $Json=$Body|ConvertTo-Json -Depth 20; Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Post -Body $Json -ErrorAction Stop }

function Get-List {
    param([string]$DocType, [array]$Fields, [array]$Filters=@(), [int]$Limit=500)
    $fieldsJson = $Fields | ConvertTo-Json -Compress
    $path = "/api/resource/$(Enc $DocType)?fields=$(Enc $fieldsJson)&limit_page_length=$Limit"
    if ($Filters.Count -gt 0) { $path += "&filters=$(Enc ($Filters | ConvertTo-Json -Compress -Depth 10))" }
    try { return @((Invoke-ErpGet -Path $path).data) } catch { Write-Host "GET LIST FAILED $DocType : $($_.Exception.Message)" -ForegroundColor Red; return @() }
}

$TargetDocTypes = @("Dispatch Case", "Stock Entry", "Sales Invoice", "Payment Entry", "Task", "Item", "Item Group", "Item Attribute", "UOM")
$TargetRoles = @("Ops - Order Creating", "Ops - Order Accepting", "Ops - Accounting", "Ops - Inventory", "Ops - Returns", "Delivery Driver", "Ops - Directors", "Ops - Delivery", "Ops - Finance")

Write-Host "=== Alternative ERPNext Permission Diagnostic ===" -ForegroundColor Cyan
Write-Host "This checks multiple possible storage locations and role-permission-manager API output." -ForegroundColor Cyan
Write-Host ""

Write-Host "1) Checking Permission Manager API for each DocType..." -ForegroundColor Yellow
$ManagerResults = @()
foreach ($dt in $TargetDocTypes) {
    try {
        $resp = Invoke-ErpPost -Path "/api/method/frappe.permissions.get_role_permissions" -Body @{ doctype = $dt }
        $msg = $resp.message
        $rows = @()
        if ($msg.permissions) { $rows = @($msg.permissions) }
        elseif ($msg -is [array]) { $rows = @($msg) }
        else { $rows = @($msg) }
        $targetRows = $rows | Where-Object { $_.role -in $TargetRoles }
        $ManagerResults += [pscustomobject]@{ doctype=$dt; api_ok=$true; row_count=@($rows).Count; target_role_rows=@($targetRows).Count; error=$null }
        if (@($targetRows).Count -gt 0) {
            Write-Host "  $dt : found target role rows via Permission Manager API" -ForegroundColor Green
            $targetRows | Select-Object role, permlevel, read, write, create, submit, cancel, if_owner, apply_user_permissions | Format-Table -AutoSize
        } else {
            Write-Host "  $dt : no target role rows from Permission Manager API (total rows: $(@($rows).Count))" -ForegroundColor Yellow
        }
    } catch {
        $ManagerResults += [pscustomobject]@{ doctype=$dt; api_ok=$false; row_count=0; target_role_rows=0; error=$_.Exception.Message }
        Write-Host "  $dt : Permission Manager API failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "2) Checking Custom DocPerm with broader filters..." -ForegroundColor Yellow
$AllCustom = Get-List -DocType "Custom DocPerm" -Fields @("name", "parent", "role", "read", "write", "create", "submit", "cancel", "permlevel", "if_owner", "apply_user_permissions") -Limit 5000
$RelevantCustom = $AllCustom | Where-Object { $_.parent -in $TargetDocTypes -or $_.role -in $TargetRoles }
Write-Host "Custom DocPerm total fetched: $(@($AllCustom).Count)"
Write-Host "Relevant Custom DocPerm rows: $(@($RelevantCustom).Count)"
if (@($RelevantCustom).Count -gt 0) {
    $RelevantCustom | Sort-Object parent, role | Format-Table parent, role, permlevel, read, write, create, submit, cancel, if_owner, apply_user_permissions -AutoSize
}
Write-Host ""

Write-Host "3) Checking standard DocType permission child rows..." -ForegroundColor Yellow
$StandardRows = @()
foreach ($dt in $TargetDocTypes) {
    try {
        $doc = (Invoke-ErpGet -Path "/api/resource/DocType/$(Enc $dt)").data
        if ($doc.permissions) {
            foreach ($p in @($doc.permissions)) {
                if ($p.role -in $TargetRoles) { $StandardRows += ($p | Add-Member -NotePropertyName parent -NotePropertyValue $dt -PassThru) }
            }
        }
    } catch { Write-Host "  DocType fetch failed $dt : $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host "Target standard permission rows: $(@($StandardRows).Count)"
if (@($StandardRows).Count -gt 0) {
    $StandardRows | Sort-Object parent, role | Format-Table parent, role, permlevel, read, write, create, submit, cancel, if_owner, apply_user_permissions -AutoSize
}
Write-Host ""

Write-Host "4) Checking if user roles are different from expected role names..." -ForegroundColor Yellow
$Roles = Get-List -DocType "Role" -Fields @("name", "role_name", "disabled") -Limit 1000
$OpsRoles = $Roles | Where-Object { $_.name -like "*Ops*" -or $_.role_name -like "*Ops*" -or $_.name -like "*Driver*" -or $_.role_name -like "*Driver*" }
$OpsRoles | Sort-Object name | Format-Table name, role_name, disabled -AutoSize

$Out = [ordered]@{
    checked_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    permission_manager_results = $ManagerResults
    relevant_custom_docperm = $RelevantCustom
    relevant_standard_docperm = $StandardRows
    ops_roles = $OpsRoles
}
$Out | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $PSScriptRoot "role-permission-alternative-diagnostic.json") -Encoding UTF8
