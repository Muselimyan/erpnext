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

# Change condition: show Accept button only if NOT already accepted by current user
$old = 'if (!frm.is_new() && ["Open", "Working"].includes(frm.doc.status)) {'
$new = 'if (!frm.is_new() && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {'

if (-not $original.Contains($old)) {
    Write-Host "Pattern not found." -ForegroundColor Red
    exit 1
}

$fixed = $original.Replace($old, $new)
$bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $csName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
Write-Host "Done. Accept button hides after current user accepts, visible to all others." -ForegroundColor Green
