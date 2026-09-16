# ==============================================================
# W10 - Retire the Distribute Payment task kind
# (Group 11 financial tail rebuild)
#
# Footprint before this script:
#   Tasks ever created with this kind ......... 0
#   Server script .......................... disabled from the start
#   Task Access Policy record ................ present
#   Workspace links .......................... none
#   task_kind Select option .................. present
#   TFV map entry ............................ present (custom_case_profit)
#
# It was a planned step in a payment-distribution flow that was never adopted:
# Group 3's audit recorded it as "intentionally out of active flow, do not
# enable unless the business flow changes". Nothing creates it, nothing reads
# it, and leaving it in the task_kind dropdown offers users a state the system
# cannot service.
#
# Removes, in dependency order: the Select option, the Task Access Policy
# record, and the disabled Server Script. Refuses if any task of this kind
# exists, so it can never delete live work.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy
# ==============================================================

param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WorkDir = Join-Path $TestRoot "work"
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

$KIND = "Distribute Payment"

Write-Host "W10 retire '$KIND' -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── Safety: refuse if any task of this kind exists ────────────────────
$inUse = 0
try {
    $rows = (Invoke-Erp Get "/api/resource/Task?limit_page_length=0&fields=$(Enc '["name"]')&filters=$(Enc ('{"task_kind":["=","' + $KIND + '"]}'))").data
    $inUse = @($rows).Count
} catch {}
Write-Host ("[0] Tasks with kind '{0}': {1}" -f $KIND, $inUse) -ForegroundColor $(if ($inUse -gt 0) { "Red" } else { "DarkGray" })
if ($inUse -gt 0 -and $Mode -eq "Deploy") {
    throw "Refusing to retire '$KIND': $inUse task(s) exist. Reassign or cancel them first."
}

# ── 1. Remove the Select option from Task.task_kind ───────────────────
Write-Host ""
Write-Host "[1] Task.task_kind option" -ForegroundColor Magenta
$tk = Get-ErpDoc "Custom Field" "Task-task_kind"
if (-not $tk) {
    Write-Host "  Task-task_kind custom field not found -- SKIP" -ForegroundColor Red
} else {
    $opts = ([string]$tk.options) -split "`n"
    $present = $false
    foreach ($o in $opts) { if ($o.Trim() -eq $KIND) { $present = $true } }
    if ($Mode -eq "Check") {
        Write-Host ("  option present: {0}" -f $present) -ForegroundColor $(if ($present) { "Yellow" } else { "DarkGray" })
    } elseif ($present) {
        $kept = @()
        foreach ($o in $opts) { if ($o.Trim() -ne $KIND) { $kept += $o } }
        Invoke-Erp Put "/api/resource/$(Enc 'Custom Field')/$(Enc 'Task-task_kind')" @{ options = ($kept -join "`n") } | Out-Null
        Write-Host "  option REMOVED" -ForegroundColor Green
    } else {
        Write-Host "  already removed" -ForegroundColor DarkGray
    }
}

# ── 2. Delete the Task Access Policy record ───────────────────────────
Write-Host ""
Write-Host "[2] Task Access Policy" -ForegroundColor Magenta
$policy = Get-ErpDoc "Task Access Policy" $KIND
if (-not $policy) {
    Write-Host "  already gone" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  WOULD DELETE" -ForegroundColor Yellow
} else {
    Invoke-Erp Delete "/api/resource/$(Enc 'Task Access Policy')/$(Enc $KIND)" | Out-Null
    Write-Host "  DELETED" -ForegroundColor Green
}

# ── 3. Delete the disabled server script ──────────────────────────────
Write-Host ""
Write-Host "[3] Server script" -ForegroundColor Magenta
$SCRIPT = "Payment Entry-after-submit-distribute-payment"
$ss = Get-ErpDoc "Server Script" $SCRIPT
if (-not $ss) {
    Write-Host "  already gone" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host ("  WOULD DELETE (disabled={0})" -f $ss.disabled) -ForegroundColor Yellow
} else {
    Invoke-Erp Delete "/api/resource/$(Enc 'Server Script')/$(Enc $SCRIPT)" | Out-Null
    Write-Host "  DELETED" -ForegroundColor Green
}

# ── 4. Client script (TFV map no longer references the kind) ──────────
Write-Host ""
Write-Host "[4] Client scripts" -ForegroundColor Magenta
$cPath = Join-Path $WorkDir "client\Task-Field-Visibility.js"
$cBody = Read-WorkScript $cPath
$cExisting = Get-ErpDoc "Client Script" "Task-Field-Visibility"
if ($Mode -eq "Check") {
    $state = if ($cExisting -and ([string]$cExisting.script) -eq $cBody) { "identical" } else { "DIFFERS" }
    Write-Host ("  {0,-30} {1}" -f "Task-Field-Visibility", $state)
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc 'Task-Field-Visibility')" @{ script = $cBody; enabled = 1 } | Out-Null
    Write-Host ("  {0,-30} UPDATED" -f "Task-Field-Visibility") -ForegroundColor Green
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
