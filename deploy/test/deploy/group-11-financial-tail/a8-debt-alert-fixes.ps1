# ==============================================================
# A8 - two defects in the Debt Alert scheduler that no other scheduler had.
#
# 1. A CANCELLED ALERT WAS TREATED AS AN OPEN ALERT.
#    The dedupe filter was `status != "Completed"`, so a Cancelled Debt Alert
#    counted as existing. The next hourly run refilled that same task with new
#    figures and reassigned it, instead of raising a fresh one -- silently
#    undoing the Director's cancellation with no trace that it had happened.
#    Every other scheduler and handler in this flow already excluded both
#    terminal statuses. Now `status not in ["Completed", "Cancelled"]`.
#
# 2. custom_assigned_to WAS NEVER SET.
#    assign_single_owner writes _assign and the ToDo -- which drive the list
#    view and notifications -- but not custom_assigned_to, which AGENTS.md
#    designates the application's single source of truth for assignment. So
#    every Debt Alert ever raised read as unassigned to anything that asks the
#    application who owns it. Now set on creation AND on update, because
#    assign_single_owner can move the owner and the two branches must not
#    produce documents in different states.
#
# One file, one Server Script. No schema change, nothing destructive.
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

Write-Host "A8 Debt Alert fixes -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

$Name = "Scheduled-debt-collection"
$Path = Join-Path $WorkDir "server\Scheduled-debt-collection.py"
if (-not (Test-Path $Path)) { throw "Missing work file: $Path" }
$Body = Read-WorkScript $Path

# ── Assert the fixes are actually in the body being uploaded ───────────
# Comments are stripped before these checks so a description of the old
# behaviour cannot satisfy a test for the new behaviour -- the mistake the D1
# bypass assertions made.
$Code = ($Body -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

Write-Host "[1] Assert the change is present in the code, not just the comments" -ForegroundColor Magenta
if ($Code -match '"status"\s*:\s*\[\s*"!="\s*,\s*"Completed"\s*\]') {
    throw "Refusing to deploy: the old dedupe filter (status != Completed) is still live code."
}
if ($Code -notmatch '"not in"\s*,\s*\[\s*"Completed"\s*,\s*"Cancelled"\s*\]') {
    throw "Refusing to deploy: the new dedupe filter (not in Completed/Cancelled) was not found in live code."
}
Write-Host "  dedupe excludes Cancelled" -ForegroundColor Green
$assignHits = ([regex]::Matches($Code, 'custom_assigned_to')).Count
if ($assignHits -lt 2) {
    throw "Refusing to deploy: expected custom_assigned_to on BOTH the create and update branches, found $assignHits occurrence(s) in live code."
}
Write-Host ("  custom_assigned_to set on both branches ({0} references)" -f $assignHits) -ForegroundColor Green
Write-Host ""

# ── Deploy ────────────────────────────────────────────────────────────
Write-Host "[2] Server Script" -ForegroundColor Magenta
$existing = Get-ErpDoc "Server Script" $Name
if (-not $existing) { throw "$Name does not exist on the server." }
$same = ($existing.script -replace "`r`n", "`n").TrimEnd() -eq ($Body -replace "`r`n", "`n").TrimEnd()
if ($Mode -eq "Check") {
    Write-Host ("  {0,-34} {1}" -f $Name, $(if ($same) { "identical" } else { "DIFFERS (cur=$($existing.script.Length) new=$($Body.Length))" })) -ForegroundColor $(if ($same) { "DarkGray" } else { "Yellow" })
    Write-Host ""
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Yellow
    exit 0
}
if ($same) {
    Write-Host ("  {0,-34} identical" -f $Name) -ForegroundColor DarkGray
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $Name)" @{ script = $Body } | Out-Null
    Write-Host ("  {0,-34} UPDATED" -f $Name) -ForegroundColor Green
}
Write-Host ""
Write-Host "[Deploy] done. Now run:" -ForegroundColor Cyan
Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
Write-Host "  then a8-verify-debt-alert.py" -ForegroundColor DarkGray
Write-Host ""
Write-Host "NOTE: this is a Scheduler Event. Saving it proves nothing -- it must be" -ForegroundColor Yellow
Write-Host "executed to be verified. The verification calls it directly." -ForegroundColor Yellow
