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

$oldCondition = 'if (!frm.is_new() && frm.doc.custom_is_team_queue_task && frm.doc.custom_team_queue_status === "Open For Team") {'
$newCondition = 'if (!frm.is_new() && ["Open", "Working"].includes(frm.doc.status)) {'

if (-not $original.Contains($oldCondition)) {
    Write-Host "Old condition not found. Current script:" -ForegroundColor Red
    $original
    exit 1
}

$fixed = $original.Replace($oldCondition, $newCondition)
$bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $csName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
Write-Host "Fixed. Accept button now shows for any Open/Working task." -ForegroundColor Green
Write-Host "Reload the Task form to see the button." -ForegroundColor Yellow
