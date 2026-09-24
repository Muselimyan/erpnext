# ==============================================================
# D3 - Re-enable the assignment invariant. Closes Group 1 ACT-07.
#
# Creates:
#   Has Role   office.team@example.com -> Ops - Order Accepting
#
# Updates:
#   Task-before-save-policy   uncomments the three assignment checks
#
# WHY THE ROLE GRANT IS NOT OPTIONAL. office.team@example.com holds NO roles at
# all, and is default_team_user for Return Call, Other, Other: Entry and
# Other: Processing. Check 2 below has no status guard, so it fires on the first
# save of a newly created task. Every NEW Return Call -- raised by the flow
# whenever a delivery with returns expected completes -- would throw, breaking
# the returns branch for all new cases. That is a live configuration defect, not
# legacy test data.
#
# Ops - Order Accepting is in the allowed_roles of all four of those policies
# (verified: the roles common to all four are Ops - Order Accepting and
# Ops - Returns). It is also the front-office role order.team already holds, and
# office.team is the ONLY team placeholder on the instance without a role -- every
# other one holds exactly the role matching its name. So granting is the right
# fix rather than editing four policies.
#
# THE THREE CHECKS HAVE DIFFERENT TRIGGERS, which is what makes this survivable:
#   check 1  exactly-1 assignee   skipped for Open / Working
#   check 2  owner holds role     NO status guard - fires on every save
#   check 3  1 assignee to close  completion only
#
# MEASURED IMPACT on legacy data before enabling (d0d):
#   check 1 blocks     0 tasks  (all 3,233 empty-_assign tasks are Open/Working)
#   check 2 blocks   701 tasks  (691 Administrator-owned seed data)
#   check 3 blocks completion for 3,233
# Test data is synthetic and deliberately not reconciled, so these refusals are
# accepted. New work is unaffected once the role grant above is in place.
#
# SAVING A SERVER SCRIPT DOES NOT PROVE IT RUNS. user_has_allowed_role() has
# never executed -- it was defined but unreachable while the block was commented.
# d3-verify exercises the role-check path explicitly; do not skip it.
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

$OFFICE = "office.team@example.com"
$ROLE = "Ops - Order Accepting"

Write-Host "D3 assignment validation -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

function Normalize([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace "`r`n", "`n").Trim()
}

# ── 0. Pre-flight ─────────────────────────────────────────────────────
Write-Host "[0] Pre-flight" -ForegroundColor Magenta
if (-not (Get-ErpDoc "Role" $ROLE)) { throw "Role '$ROLE' does not exist." }
$ou = Get-ErpDoc "User" $OFFICE
if (-not $ou) { throw "User '$OFFICE' does not exist." }
Write-Host ("  {0,-46} {1}" -f "Role '$ROLE'", "present") -ForegroundColor Green
Write-Host ("  {0,-46} {1}" -f "User '$OFFICE'", "present") -ForegroundColor Green
$hasRole = $false
foreach ($r in ($ou.roles | Where-Object { $_ })) { if ($r.role -eq $ROLE) { $hasRole = $true } }
Write-Host ("  {0,-46} {1}" -f "office.team already holds the role", $(if ($hasRole) { "yes" } else { "NO - will grant" })) -ForegroundColor $(if ($hasRole) { "DarkGray" } else { "Yellow" })
Write-Host ""

# ── 1. Role grant ─────────────────────────────────────────────────────
Write-Host "[1] Role grant" -ForegroundColor Magenta
if ($hasRole) {
    Write-Host ("  {0,-46} SAME" -f "$OFFICE -> $ROLE") -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host ("  {0,-46} WOULD GRANT" -f "$OFFICE -> $ROLE") -ForegroundColor Yellow
} else {
    # Append to the child table rather than replacing it, so any other role the
    # user gains later is not silently dropped by this script.
    $existing = @()
    foreach ($r in ($ou.roles | Where-Object { $_ })) { $existing += @{ role = $r.role } }
    $existing += @{ role = $ROLE }
    Invoke-Erp Put "/api/resource/$(Enc 'User')/$(Enc $OFFICE)" @{ roles = $existing } | Out-Null
    Write-Host ("  {0,-46} GRANTED" -f "$OFFICE -> $ROLE") -ForegroundColor Green
}
Write-Host ""

# ── 2. Server Script ──────────────────────────────────────────────────
Write-Host "[2] Server Script" -ForegroundColor Magenta
$name = "Task-before-save-policy"
$path = Join-Path $WorkDir "server\$name.py"
if (-not (Test-Path $path)) { throw "Work file not found: $path" }
$localRaw = Read-WorkScript $path
$local = Normalize $localRaw
$code = (($local -split "`n") | ForEach-Object { ($_ -split "#", 2)[0] }) -join "`n"

# Assert the three checks are live in CODE, not merely present as comments.
$need = @(
    'must be assigned to exactly 1 user',
    'user_has_allowed_role(owner, allowed_roles)',
    'Assign exactly 1 owner before completing'
)
$missing = @()
foreach ($t in $need) { if ($code -notmatch [regex]::Escape($t)) { $missing += $t } }
if ($missing.Count -gt 0) {
    throw "Refusing to deploy '$name': the assignment checks are not live in code. Missing: $($missing -join ' | ')"
}

$doc = Get-ErpDoc "Server Script" $name
if (-not $doc) { throw "Server Script '$name' does not exist on $BaseUrl." }
if ($local -eq (Normalize $doc.script)) {
    Write-Host ("  {0,-46} SAME" -f $name) -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host ("  {0,-46} DIFFERS" -f $name) -ForegroundColor Yellow
    $remoteCode = ((((Normalize $doc.script) -split "`n") | ForEach-Object { ($_ -split "#", 2)[0] }) -join "`n")
    $rlive = if ($remoteCode -match "must be assigned to exactly 1 user") { "live" } else { "commented out" }
    Write-Host ("      assignment checks  server={0}  local=live" -f $rlive) -ForegroundColor Yellow
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $name)" @{ script = $localRaw } | Out-Null
    Write-Host ("  {0,-46} UPDATED" -f $name) -ForegroundColor Green
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "[Check] Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "[Deploy] done." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Clear the cache, then verify. EXECUTE the verify script -- a Server Script that" -ForegroundColor Yellow
    Write-Host "compiles is not proven to run, and user_has_allowed_role has never executed." -ForegroundColor Yellow
    Write-Host "  ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "    `"docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Get-Content deploy\test\deploy\group-1-dispatch-operational\d3-verify-assignment.py | ``" -ForegroundColor DarkGray
    Write-Host "    ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "      `"docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "ROLLBACK: re-comment the block in $name and redeploy." -ForegroundColor DarkGray
}
