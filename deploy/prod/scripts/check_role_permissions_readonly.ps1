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

function Get-CustomDocPermRows {
    param([string]$DocType)
    try {
        $fields = @("name", "parent", "role", "read", "write", "create", "submit", "cancel", "delete", "permlevel", "if_owner", "apply_user_permissions") | ConvertTo-Json -Compress
        $filters = @(@("parent", "=", $DocType)) | ConvertTo-Json -Compress
        $path = "/api/resource/Custom DocPerm?fields=$(Enc $fields)&filters=$(Enc $filters)&limit_page_length=500"
        return @((Invoke-ErpGet -Path $path).data)
    } catch {
        return @()
    }
}

function Get-DocTypePermRows {
    param([string]$DocType)
    try {
        $doc = (Invoke-ErpGet -Path "/api/resource/DocType/$(Enc $DocType)").data
        if ($doc.permissions) { return @($doc.permissions) }
    } catch {}
    return @()
}

function Test-HasPerm {
    param($Rows, [string]$Role, [string]$Perm)
    return (($Rows | Where-Object {
        $_.role -eq $Role -and
        $_.$Perm -eq 1 -and
        (($_.permlevel -eq 0) -or ($null -eq $_.permlevel))
    }).Count -gt 0)
}

$Expected = @(
    @{doctype="Dispatch Case"; role="Ops - Order Creating"; read=1; write=1; create=1; submit=1; cancel=0},
    @{doctype="Dispatch Case"; role="Ops - Order Accepting"; read=1; write=0; create=0; submit=0; cancel=0},
    @{doctype="Dispatch Case"; role="Ops - Accounting"; read=1; write=0; create=0; submit=0; cancel=0},
    @{doctype="Dispatch Case"; role="Ops - Inventory"; read=1; write=0; create=0; submit=0; cancel=0},
    @{doctype="Dispatch Case"; role="Ops - Returns"; read=1; write=0; create=0; submit=0; cancel=0},
    @{doctype="Dispatch Case"; role="Delivery Driver"; read=1; write=0; create=0; submit=0; cancel=0},
    @{doctype="Dispatch Case"; role="Ops - Directors"; read=1; write=0; create=0; submit=0; cancel=1},

    @{doctype="Stock Entry"; role="Ops - Inventory"; read=1; write=1; create=1; submit=1; cancel=0},
    @{doctype="Stock Entry"; role="Ops - Delivery"; read=1; write=1; create=1; submit=1; cancel=0},
    @{doctype="Stock Entry"; role="Ops - Returns"; read=1; write=1; create=1; submit=1; cancel=0},
    @{doctype="Stock Entry"; role="Delivery Driver"; read=0; write=0; create=0; submit=0; cancel=0},

    @{doctype="Sales Invoice"; role="Ops - Accounting"; read=1; write=1; create=1; submit=1; cancel=1},
    @{doctype="Sales Invoice"; role="Ops - Finance"; read=1; write=0; create=0; submit=0; cancel=0},

    @{doctype="Payment Entry"; role="Ops - Accounting"; read=1; write=1; create=1; submit=1; cancel=1},
    @{doctype="Payment Entry"; role="Ops - Finance"; read=1; write=1; create=1; submit=1; cancel=1},

    @{doctype="Task"; role="Ops - Finance"; read=1; write=1; create=0; submit=0; cancel=0}
)

foreach ($dt in @("Item", "Item Group", "Item Attribute", "UOM")) {
    $Expected += @{doctype=$dt; role="Ops - Inventory"; read=1; write=1; create=1; submit=0; cancel=0}
    $Expected += @{doctype=$dt; role="Ops - Directors"; read=1; write=1; create=1; submit=0; cancel=0}
}

$DocTypes = $Expected | ForEach-Object { $_.doctype } | Sort-Object -Unique
$RowsByDoc = @{}
foreach ($dt in $DocTypes) {
    $RowsByDoc[$dt] = @((Get-CustomDocPermRows -DocType $dt) + (Get-DocTypePermRows -DocType $dt))
}

$Results = @()
foreach ($e in $Expected) {
    $rows = $RowsByDoc[$e.doctype]
    $issues = @()
    foreach ($perm in @("read", "write", "create", "submit", "cancel")) {
        $has = Test-HasPerm -Rows $rows -Role $e.role -Perm $perm
        if ($e.$perm -eq 1 -and -not $has) { $issues += "missing_$perm" }
        if ($e.$perm -eq 0 -and $has -and $e.doctype -eq "Stock Entry" -and $e.role -eq "Delivery Driver") { $issues += "should_not_have_$perm" }
    }
    $Results += [pscustomobject]@{
        doctype = $e.doctype
        role = $e.role
        status = if ($issues.Count -eq 0) { "OK" } else { "ISSUE" }
        issue = ($issues -join ", ")
    }
}

$Results | Format-Table -AutoSize
$IssueCount = ($Results | Where-Object { $_.status -eq "ISSUE" }).Count
Write-Host ""
Write-Host "Role permission check issues: $IssueCount"
$Results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot "role-permission-check-readonly.json") -Encoding UTF8
if ($IssueCount -gt 0) { exit 1 }
