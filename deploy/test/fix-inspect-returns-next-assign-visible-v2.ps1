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
    try {
        return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)?fields=[`"name`",`"script`",`"enabled`",`"modified`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    } catch {
        return $null
    }
}
function Save-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}
function New-ErpDoc([string]$DocType, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

$ScriptName = "Task-Inspect Returns Next Assign Visible"
$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_inspect_returns_next_assign_visible(frm);
        setTimeout(function() { task_inspect_returns_next_assign_visible(frm); }, 300);
        setTimeout(function() { task_inspect_returns_next_assign_visible(frm); }, 1000);
    },
    task_kind: function(frm) {
        task_inspect_returns_next_assign_visible(frm);
    }
});

function task_inspect_returns_next_assign_visible(frm) {
    if (!frm || !frm.doc || frm.doc.task_kind !== 'Returns processing / verification') return;
    if (!frm.fields_dict || !frm.fields_dict.custom_next_task_assign_to) return;
    frm.set_df_property('custom_next_task_assign_to', 'label', 'Next Task: Assign To');
    frm.set_df_property('custom_next_task_assign_to', 'hidden', 0);
    frm.toggle_display('custom_next_task_assign_to', true);
    if (frm.fields_dict.custom_next_task_assign_to.$wrapper) {
        frm.fields_dict.custom_next_task_assign_to.$wrapper.show();
    }
}
'@

Write-Host "=== Inspect Returns Next Task assignment visibility v2 ===" -ForegroundColor Cyan
Write-Host "Target: TEST only ($BaseUrl)" -ForegroundColor Yellow
Write-Host "Mode: $Mode" -ForegroundColor Yellow

$Existing = Get-ErpDoc "Client Script" $ScriptName
if ($Existing) {
    $HasExpected = ([string]$Existing.script) -match 'task_inspect_returns_next_assign_visible' -and ([int]$Existing.enabled -eq 1)
    Write-Host "Client Script exists: True"
    Write-Host "Enabled: $($Existing.enabled)"
    Write-Host "Expected code present: $HasExpected"
    if ($Mode -eq "Check") {
        if ($HasExpected) { Write-Host "Status: fixed." -ForegroundColor Green } else { Write-Host "Status: update needed." -ForegroundColor Yellow }
        return
    }
    if (-not $HasExpected) {
        $BackupPath = Join-Path $PSScriptRoot ("_backup_Task_Inspect_Returns_Next_Assign_Visible_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
        Set-Content -Path $BackupPath -Value ([string]$Existing.script) -Encoding UTF8
        Save-ErpDoc "Client Script" $ScriptName @{ script = $NewScript; enabled = 1 } | Out-Null
        Write-Host "Updated script. Backup: $BackupPath" -ForegroundColor Green
    } else {
        Write-Host "No changes needed." -ForegroundColor Green
    }
} else {
    Write-Host "Client Script exists: False"
    if ($Mode -eq "Check") {
        Write-Host "Status: create needed." -ForegroundColor Yellow
        return
    }
    New-ErpDoc "Client Script" @{
        doctype = "Client Script"
        name = $ScriptName
        dt = "Task"
        view = "Form"
        enabled = 1
        script = $NewScript
    } | Out-Null
    Write-Host "Created script: $ScriptName" -ForegroundColor Green
}

$Verify = Get-ErpDoc "Client Script" $ScriptName
$VerifyOk = $Verify -and ([string]$Verify.script) -match 'task_inspect_returns_next_assign_visible' -and ([int]$Verify.enabled -eq 1)
Write-Host "Verified: $VerifyOk" -ForegroundColor Green
if (-not $VerifyOk) { throw "Verification failed." }
Write-Host "Done. Hard refresh browser and reopen the Inspect Returns task." -ForegroundColor Green
