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

function Invoke-ErpGet {
    param([string]$Path)
    return Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -ErrorAction Stop
}

function Get-ErpList {
    param([string]$DocType, [array]$Fields, [array]$Filters = @(), [int]$Limit = 500)
    $fieldsJson = $Fields | ConvertTo-Json -Compress
    $path = "/api/resource/$(Enc $DocType)?fields=$(Enc $fieldsJson)&limit_page_length=$Limit"
    if ($Filters.Count -gt 0) {
        $filtersJson = $Filters | ConvertTo-Json -Compress -Depth 10
        $path += "&filters=$(Enc $filtersJson)"
    }
    try { return @((Invoke-ErpGet -Path $path).data) } catch { return @() }
}

$TargetRoles = @(
    "Ops - Order Creating",
    "Ops - Order Accepting",
    "Ops - Accounting",
    "Ops - Inventory",
    "Ops - Returns",
    "Delivery Driver",
    "Ops - Directors",
    "Ops - Delivery",
    "Ops - Finance"
)

$TargetDocTypes = @(
    "Dispatch Case",
    "Stock Entry",
    "Sales Invoice",
    "Payment Entry",
    "Task",
    "Item",
    "Item Group",
    "Item Attribute",
    "UOM"
)

$Expected = @(
    @{doctype="Dispatch Case"; role="Ops - Order Creating"; perms=@("read", "write", "create", "submit")},
    @{doctype="Dispatch Case"; role="Ops - Order Accepting"; perms=@("read")},
    @{doctype="Dispatch Case"; role="Ops - Accounting"; perms=@("read")},
    @{doctype="Dispatch Case"; role="Ops - Inventory"; perms=@("read")},
    @{doctype="Dispatch Case"; role="Ops - Returns"; perms=@("read")},
    @{doctype="Dispatch Case"; role="Delivery Driver"; perms=@("read")},
    @{doctype="Dispatch Case"; role="Ops - Directors"; perms=@("read", "cancel")},
    @{doctype="Stock Entry"; role="Ops - Inventory"; perms=@("read", "write", "create", "submit")},
    @{doctype="Stock Entry"; role="Ops - Delivery"; perms=@("read", "write", "create", "submit")},
    @{doctype="Stock Entry"; role="Ops - Returns"; perms=@("read", "write", "create", "submit")},
    @{doctype="Sales Invoice"; role="Ops - Accounting"; perms=@("read", "write", "create", "submit", "cancel")},
    @{doctype="Sales Invoice"; role="Ops - Finance"; perms=@("read")},
    @{doctype="Payment Entry"; role="Ops - Accounting"; perms=@("read", "write", "create", "submit", "cancel")},
    @{doctype="Payment Entry"; role="Ops - Finance"; perms=@("read", "write", "create", "submit", "cancel")},
    @{doctype="Task"; role="Ops - Finance"; perms=@("read", "write")},
    @{doctype="Item"; role="Ops - Inventory"; perms=@("read", "write", "create")},
    @{doctype="Item"; role="Ops - Directors"; perms=@("read", "write", "create")},
    @{doctype="Item Group"; role="Ops - Inventory"; perms=@("read", "write", "create")},
    @{doctype="Item Group"; role="Ops - Directors"; perms=@("read", "write", "create")},
    @{doctype="Item Attribute"; role="Ops - Inventory"; perms=@("read", "write", "create")},
    @{doctype="Item Attribute"; role="Ops - Directors"; perms=@("read", "write", "create")},
    @{doctype="UOM"; role="Ops - Inventory"; perms=@("read", "write", "create")},
    @{doctype="UOM"; role="Ops - Directors"; perms=@("read", "write", "create")}
)

Write-Host "=== ERPNext Role Permission Diagnostic ===" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl"
Write-Host ""

$RoleRows = Get-ErpList -DocType "Role" -Fields @("name", "role_name", "disabled") -Limit 500
Write-Host "Target roles:" -ForegroundColor Yellow
foreach ($role in $TargetRoles) {
    $found = $RoleRows | Where-Object { $_.name -eq $role -or $_.role_name -eq $role }
    if ($found) { Write-Host "  OK: $role" -ForegroundColor Green } else { Write-Host "  MISSING ROLE: $role" -ForegroundColor Red }
}
Write-Host ""

$AllRows = @()
$DocDiagnostics = @()
foreach ($dt in $TargetDocTypes) {
    $customRows = Get-ErpList -DocType "Custom DocPerm" -Fields @("name", "parent", "role", "read", "write", "create", "submit", "cancel", "delete", "permlevel", "if_owner", "apply_user_permissions") -Filters @(@("parent", "=", $dt)) -Limit 500
    $metaRows = @()
    $metaError = $null
    try {
        $meta = (Invoke-ErpGet -Path "/api/resource/DocType/$(Enc $dt)").data
        if ($meta.permissions) { $metaRows = @($meta.permissions) }
    } catch { $metaError = $_.Exception.Message }

    foreach ($r in $customRows) { $AllRows += $r | Add-Member -NotePropertyName source -NotePropertyValue "Custom DocPerm" -PassThru }
    foreach ($r in $metaRows) { $AllRows += $r | Add-Member -NotePropertyName source -NotePropertyValue "DocType.permissions" -PassThru }

    $DocDiagnostics += [pscustomobject]@{
        doctype = $dt
        custom_docperm_count = @($customRows).Count
        doctype_permission_count = @($metaRows).Count
        meta_error = $metaError
    }
}

Write-Host "DocType permission row counts:" -ForegroundColor Yellow
$DocDiagnostics | Format-Table -AutoSize
Write-Host ""

$RelevantRows = $AllRows | Where-Object { $_.role -in $TargetRoles }
Write-Host "Actual ERPNext permission rows for target roles:" -ForegroundColor Yellow
if (@($RelevantRows).Count -eq 0) {
    Write-Host "  No matching permission rows found for target roles." -ForegroundColor Red
} else {
    $RelevantRows |
        Select-Object source, parent, role, permlevel, read, write, create, submit, cancel, if_owner, apply_user_permissions |
        Sort-Object parent, role, source |
        Format-Table -AutoSize
}
Write-Host ""

$Compare = @()
foreach ($e in $Expected) {
    $rows = @($AllRows | Where-Object { $_.parent -eq $e.doctype -and $_.role -eq $e.role -and (($_.permlevel -eq 0) -or ($null -eq $_.permlevel)) })
    $missing = @()
    foreach ($perm in $e.perms) {
        if ((@($rows | Where-Object { $_.$perm -eq 1 }).Count) -eq 0) { $missing += $perm }
    }
    $Compare += [pscustomobject]@{
        doctype = $e.doctype
        role = $e.role
        expected = ($e.perms -join ",")
        status = if ($missing.Count -eq 0) { "OK" } else { "ISSUE" }
        missing = ($missing -join ",")
        rows_found = @($rows).Count
    }
}

Write-Host "Expected permission comparison:" -ForegroundColor Yellow
$Compare | Format-Table -AutoSize
Write-Host ""
$IssueCount = @($Compare | Where-Object { $_.status -eq "ISSUE" }).Count
Write-Host "Comparison issues: $IssueCount"

$Out = [ordered]@{
    checked_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    role_diagnostics = $TargetRoles | ForEach-Object {
        $role = $_
        $found = $RoleRows | Where-Object { $_.name -eq $role -or $_.role_name -eq $role }
        [ordered]@{ role = $role; exists = [bool]$found; disabled = if ($found) { $found[0].disabled } else { $null } }
    }
    doctype_diagnostics = $DocDiagnostics
    relevant_permission_rows = $RelevantRows
    comparison = $Compare
    issue_count = $IssueCount
}
$Out | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $PSScriptRoot "role-permission-diagnostic.json") -Encoding UTF8

if ($IssueCount -gt 0) { exit 1 }
