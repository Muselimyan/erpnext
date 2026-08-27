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
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)?fields=[`"name`",`"script`",`"enabled`",`"modified`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
}
function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

$ScriptName = "Task-Accept Start"
$Client = Get-ErpDoc "Client Script" $ScriptName
$Script = [string]$Client.script

$Marker = @'
        if (frm.doc.task_kind === "Account Details: Entry" && frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property("custom_next_task_assign_to", "hidden", 0); frm.toggle_display("custom_next_task_assign_to", true); }
'@

$Insert = @'
        if (frm.doc.task_kind === "Returns processing / verification" && frm.fields_dict.custom_next_task_assign_to) {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
            frm.toggle_display("custom_next_task_assign_to", true);
        }
'@

Write-Host "=== Inspect Returns Next Task assignment visibility ===" -ForegroundColor Cyan
Write-Host "Target: TEST only ($BaseUrl)" -ForegroundColor Yellow
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Client Script: $ScriptName modified $($Client.modified)" -ForegroundColor Gray

$HasDispatchKind = $Script -match 'Returns processing / verification'
$HasForceBlock = $Script -match 'frm\.doc\.task_kind === "Returns processing / verification"[\s\S]*?frm\.toggle_display\("custom_next_task_assign_to", true\)'

Write-Host "Returns processing in dispatchKinds: $HasDispatchKind"
Write-Host "Forced visible block present: $HasForceBlock"

if (-not $HasDispatchKind) {
    throw "Task-Accept Start does not contain Returns processing / verification in dispatch workflow task kinds. No changes made."
}

if ($Mode -eq "Check") {
    if ($HasForceBlock) {
        Write-Host "Status: already fixed." -ForegroundColor Green
    } else {
        Write-Host "Status: patch needed. Run with -Mode Deploy to apply." -ForegroundColor Yellow
    }
    return
}

if ($HasForceBlock) {
    Write-Host "No changes needed." -ForegroundColor Green
    return
}

if (-not $Script.Contains($Marker)) {
    throw "Expected Account Details next-assign marker not found. No changes made."
}

$BackupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_before_inspect_returns_next_assign_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
Set-Content -Path $BackupPath -Value $Script -Encoding UTF8

$Updated = $Script.Replace($Marker, $Insert + $Marker)
Put-ErpDoc "Client Script" $ScriptName @{ script = $Updated; enabled = 1 } | Out-Null

$Verify = Get-ErpDoc "Client Script" $ScriptName
$VerifyScript = [string]$Verify.script
$VerifyForceBlock = $VerifyScript -match 'frm\.doc\.task_kind === "Returns processing / verification"[\s\S]*?frm\.toggle_display\("custom_next_task_assign_to", true\)'

Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
Write-Host "Forced visible block present after deploy: $VerifyForceBlock" -ForegroundColor Green
if (-not $VerifyForceBlock) { throw "Deploy verification failed." }
Write-Host "Done. Hard refresh browser and reopen the Inspect Returns task." -ForegroundColor Green
