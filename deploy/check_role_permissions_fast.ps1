param()

. "$PSScriptRoot\export.ps1"

function Get-DocPermRows($Doc) {
    $rows = @()
    try {
        $meta = Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/$([uri]::EscapeDataString($Doc))"
        if ($meta.data.permissions) { $rows += $meta.data.permissions }
    } catch {}
    try {
        $filters = ConvertTo-Json @(@("Custom DocPerm", "parent", "=", $Doc)) -Compress
        $fields = ConvertTo-Json @("name", "parent", "role", "read", "write", "create", "submit", "cancel", "permlevel") -Compress
        $resp = Invoke-ErpRequest -Method Get -Path "/api/resource/Custom DocPerm?fields=$([uri]::EscapeDataString($fields))&filters=$([uri]::EscapeDataString($filters))&limit_page_length=500"
        if ($resp.data) { $rows += $resp.data }
    } catch {}
    return $rows
}

function Has-Perm($Rows, $Role, $Field) {
    return (($Rows | Where-Object { $_.role -eq $Role -and $_.$Field -eq 1 -and (($_.permlevel -eq 0) -or ($null -eq $_.permlevel)) }).Count -gt 0)
}

$expected = @(
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
    $expected += @{doctype=$dt; role="Ops - Inventory"; read=1; write=1; create=1; submit=0; cancel=0}
    $expected += @{doctype=$dt; role="Ops - Directors"; read=1; write=1; create=1; submit=0; cancel=0}
}

$docTypes = $expected | ForEach-Object { $_.doctype } | Sort-Object -Unique
$permByDoc = @{}
foreach ($doc in $docTypes) { $permByDoc[$doc] = @(Get-DocPermRows $doc) }

$results = @()
foreach ($e in $expected) {
    $rows = $permByDoc[$e.doctype]
    $issues = @()
    foreach ($p in @("read", "write", "create", "submit", "cancel")) {
        $actual = Has-Perm $rows $e.role $p
        if ($e.$p -eq 1 -and -not $actual) { $issues += "missing_$p" }
        if ($e.$p -eq 0 -and $actual -and $e.doctype -eq "Stock Entry" -and $e.role -eq "Delivery Driver") { $issues += "should_not_have_$p" }
    }
    $results += [pscustomobject]@{ doctype=$e.doctype; role=$e.role; status=if($issues.Count -eq 0){"OK"}else{"ISSUE"}; issue=($issues -join ", ") }
}

$results | Format-Table -AutoSize
$issueCount = ($results | Where-Object { $_.status -eq "ISSUE" }).Count
Write-Host "`nRole permission check issues: $issueCount"
$results | ConvertTo-Json -Depth 5 | Set-Content "$PSScriptRoot\role-permission-check-fast.json" -Encoding UTF8
if ($issueCount -gt 0) { exit 1 }
