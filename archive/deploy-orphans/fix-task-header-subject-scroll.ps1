#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$Name = "Task-Accept Start"
Write-Host "=== Task Header Subject Scroll ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasOptionA = $script -match 'task_header_option_a_fix'
$hasScroll = $script -match 'task-subject-scroll-v1'
Write-Host "Has Option A fix: $(if($hasOptionA){'Yes'}else{'No'})"
Write-Host "Has scrollable subject: $(if($hasScroll){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasOptionA -and $hasScroll) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $hasOptionA) { throw "Option A header fix is missing. Deploy fix-task-header-option-a-clean.ps1 first." }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_subject_scroll_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$old = "tt.css({'display':'block','overflow':'hidden','text-overflow':'ellipsis','white-space':'nowrap','max-width':'100%'});"
$new = "tt.attr('data-task-subject-scroll', 'task-subject-scroll-v1');`n                tt.css({'display':'block','overflow-x':'auto','overflow-y':'hidden','text-overflow':'clip','white-space':'nowrap','max-width':'100%','scrollbar-width':'thin','cursor':'ew-resize'});"

if ($script.Contains($old)) {
    $script = $script.Replace($old, $new)
} elseif (-not $hasScroll) {
    throw "Could not find title CSS line to replace"
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Scrollable subject header patch deployed" -ForegroundColor Green
