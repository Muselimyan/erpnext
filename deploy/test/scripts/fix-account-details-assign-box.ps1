$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$Name = "Task-Account Details UI Cleanup"
$Doc = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 20).data
$Script = [string]$Doc.script

if ($Script -notmatch 'custom_assigned_to') {
    $target1 = @'
        var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
'@
    $replace1 = @'
        var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
        var assignedControl = wrapper.find('[data-fieldname="custom_assigned_to"]').closest('.frappe-control');
'@
    if (-not $Script.Contains($target1)) { throw "Expected priorityControl block not found; refusing broad edit." }
    $Script = $Script.Replace($target1, $replace1)

    $target2 = @'
            if (priorityControl.length) priorityControl.appendTo(leftColumn);
'@
    $replace2 = @'
            if (priorityControl.length) priorityControl.appendTo(leftColumn);
            if (assignedControl.length) assignedControl.appendTo(leftColumn);
'@
    if (-not $Script.Contains($target2)) { throw "Expected priority append block not found; refusing broad edit." }
    $Script = $Script.Replace($target2, $replace2)

    $target3 = @'
                if ((fieldname && fieldname !== 'status' && fieldname !== 'priority') || ["Warehouse Pickup Photo", "Warehouse Drop-off Photo", "Scan Product Barcode", "Scan Qty", "Last Scan Result", "Product Work Warning", "Choose Product", "Product Qty", "Batch / LOT", "Unit Price"].indexOf(labelText) >= 0) {
'@
    $replace3 = @'
                if ((fieldname && fieldname !== 'status' && fieldname !== 'priority' && fieldname !== 'custom_assigned_to') || ["Warehouse Pickup Photo", "Warehouse Drop-off Photo", "Scan Product Barcode", "Scan Qty", "Last Scan Result", "Product Work Warning", "Choose Product", "Product Qty", "Batch / LOT", "Unit Price"].indexOf(labelText) >= 0) {
'@
    if (-not $Script.Contains($target3)) { throw "Expected left-column hide condition not found; refusing broad edit." }
    $Script = $Script.Replace($target3, $replace3)

    $target4 = @'
            priorityControl.show();
'@
    $replace4 = @'
            priorityControl.show();
            assignedControl.show();
'@
    if (-not $Script.Contains($target4)) { throw "Expected priority show block not found; refusing broad edit." }
    $Script = $Script.Replace($target4, $replace4)
}

$body = @{ script = $Script; enabled = 1; dt = "Task"; view = "Form" } | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Updated Account Details UI to show Assign To box only." -ForegroundColor Green

$ServerName = "Task-Account Details Default Assignment"
$Server = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $ServerName)" -Headers $Headers -Method Get -TimeoutSec 20).data
if ($Server.script -notmatch 'doc.get\("custom_assigned_to"\) or "accounting.team@example.com"') {
    throw "Server default assignment rule was not found as expected; review before changing anything else."
}
Write-Host "Verified server rule: selected Assign To wins; empty defaults to accounting.team@example.com." -ForegroundColor Green
