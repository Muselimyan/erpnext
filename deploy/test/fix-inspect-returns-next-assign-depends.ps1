#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)?fields=[`"name`",`"fieldname`",`"label`",`"hidden`",`"depends_on`",`"insert_after`",`"modified`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
}
function Save-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

$FieldName = "Task-custom_next_task_assign_to"
$ExpectedDepends = 'eval:["Other: Entry","Other: Processing","Returns processing / verification"].includes(doc.task_kind)'
$Doc = Get-ErpDoc "Custom Field" $FieldName

Write-Host "=== Inspect Returns Next Task assignment depends_on ===" -ForegroundColor Cyan
Write-Host "Target: TEST only ($BaseUrl)" -ForegroundColor Yellow
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Field: $($Doc.name) modified $($Doc.modified)" -ForegroundColor Gray
Write-Host "Current depends_on: $($Doc.depends_on)"
Write-Host "Expected depends_on: $ExpectedDepends"

$IsFixed = [string]$Doc.depends_on -eq $ExpectedDepends
if ($Mode -eq "Check") {
    if ($IsFixed) { Write-Host "Status: fixed." -ForegroundColor Green } else { Write-Host "Status: patch needed." -ForegroundColor Yellow }
    return
}

if ($IsFixed) {
    Write-Host "No changes needed." -ForegroundColor Green
    return
}

$BackupPath = Join-Path $PSScriptRoot ("_backup_Custom_Field_Task_custom_next_task_assign_to_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
$Doc | ConvertTo-Json -Depth 10 | Set-Content -Path $BackupPath -Encoding UTF8
Save-ErpDoc "Custom Field" $FieldName @{ depends_on = $ExpectedDepends; hidden = 0; label = "Next Task: Assign To"; insert_after = "custom_assigned_to" } | Out-Null

$Verify = Get-ErpDoc "Custom Field" $FieldName
$VerifyOk = [string]$Verify.depends_on -eq $ExpectedDepends -and [int]$Verify.hidden -eq 0
Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
Write-Host "Verified: $VerifyOk" -ForegroundColor Green
if (-not $VerifyOk) { throw "Verification failed." }
Write-Host "Done. Hard refresh browser and reopen the Inspect Returns task." -ForegroundColor Green
