$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$csName = "Task-Dispatch Packing Usability"
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $csName)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$original = $r.data.script

# Replace: move Accept button out of dropdown group, make it standalone primary button
$old = '            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({ method: "dispatch_task_accept", args: { task_name: frm.doc.name }, freeze: true, callback: function() { frm.reload_doc(); } });
            }, __("Dispatch & Packing Work"));'

$new = '            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({ method: "dispatch_task_accept", args: { task_name: frm.doc.name }, freeze: true, callback: function() { frm.reload_doc(); } });
            });
            frm.change_custom_button_type(__("Accept / Start Task"), null, "primary");'

if (-not $original.Contains($old)) {
    Write-Host "Exact old pattern not found. Showing current accept lines:" -ForegroundColor Red
    $lines = $original -split "`n"
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Accept|accept|custom_button') {
            Write-Host "  L$($i+1): $($lines[$i].TrimEnd())"
        }
    }
    exit 1
}

$fixed = $original.Replace($old, $new)
$bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $csName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
Write-Host "Done. Accept button is now a standalone PRIMARY button (blue, top-right)." -ForegroundColor Green
