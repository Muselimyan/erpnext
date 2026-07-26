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

$Name = "task_list_filtered"
Write-Host "=== Account Details My Tasks Users ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$script = $data.script

$hasMarker = $script -match 'ACCOUNT_DETAILS_MY_TASK_USERS'
$hasUsers = ($script -match 'sahakyan\.oli1998@gmail\.com') -and ($script -match 'ly\.aghayan@gmail\.com') -and ($script -match 'levonaghinyan77@gmail\.com')
Write-Host "Has Account details My Tasks exception: $(if($hasMarker){'Yes'}else{'No'})"
Write-Host "Has requested users: $(if($hasUsers){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasMarker -and $hasUsers) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if ($hasMarker -and $hasUsers) {
    Write-Host "Already fixed" -ForegroundColor Green
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_task_list_filtered_account_details_my_tasks_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".py")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

if (-not $hasMarker) {
    $accountUsersBlock = @'
ACCOUNT_DETAILS_MY_TASK_USERS = [
    "sahakyan.oli1998@gmail.com",
    "ly.aghayan@gmail.com",
    "levonaghinyan77@gmail.com",
]

'@
    $script = [regex]::Replace($script, '(?m)^(my_tasks\s*=\s*int\(frappe\.form_dict\.get\("my_tasks"\).*?)$', $accountUsersBlock + '$1', 1)
    if (-not ($script -match 'ACCOUNT_DETAILS_MY_TASK_USERS')) {
        throw "Could not insert ACCOUNT_DETAILS_MY_TASK_USERS block"
    }
}

if (-not ($script -match "task_kind = 'Account details'")) {
    $pattern = '(?ms)(\s+if has_my:\s*\r?\n\s+my_sql = .*?\r?\n)(\s+or_clauses\.append\(my_sql\))'
    $replacement = '$1        if user in ACCOUNT_DETAILS_MY_TASK_USERS:' + "`r`n" + '            my_sql = "(" + my_sql + " OR task_kind = ''Account details'')"' + "`r`n" + '$2'
    $script = [regex]::Replace($script, $pattern, $replacement, 1)
    if (-not ($script -match "task_kind = 'Account details'")) {
        throw "Could not patch My Tasks assignment block"
    }
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Account details My Tasks user exception deployed" -ForegroundColor Green
