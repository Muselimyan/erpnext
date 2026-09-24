# ==============================================================
# D4 + D5 + D6 - retire legacy task kinds, delete the unwritten profit field,
#                and the small fixes. Closes Group 1 ACT-04, 08, 12, 13, 14, 15.
#
# Deliberately ONE script rather than three. Each part is a handful of edits;
# three .ps1 + three verify pairs would be ceremony copied from a pattern built
# for genuine architectural surgery.
#
# ── D4: retire two task kinds ────────────────────────────────────────
#   Task.task_kind   drop "Order accepting" and "Dispatch picking / hand-off"
#                    from options; change DEFAULT to "Order entry"
#   Task-Field-Visibility.js / Task-Action Buttons.js  drop the retired kind
#
#   Doc 21 already classed "Order accepting" as legacy/unused; it is immediately
#   overwritten by Task-Accept Start.js on new tasks and no server script handles
#   it -- yet it was the field DEFAULT, so any task created outside the UI landed
#   in a kind nothing orchestrates. That default is the real fix here.
#   "Dispatch picking / hand-off" has no server reference at all and is absent
#   from doc 16; the unified flow folded it into "Pack / prepare items".
#
#   HELD BACK, on purpose: "Return drop-off at warehouse" (still gated by
#   Task-before-save-policy for legacy non-DC tasks) and "Return to warehouse
#   (aborted delivery / cancelled order)" -- that is literally the aborted-
#   delivery return kind and is the most likely consumer of the deferred cancel
#   flow. Retiring then re-adding it is avoidable churn.
#
#   d0 confirmed 0 Tasks exist in any of the four kinds, so nothing is orphaned.
#
# ── D5: delete Dispatch Case.profit ──────────────────────────────────
#   Nothing writes it. A grep across every server script returned only its two
#   SYSTEM_FIELDS allow-list entries, which go with it -- an allowance for a field
#   with no legitimate writer is a hole, per the gates' own stated rule. Profit is
#   computed into Task.custom_case_profit by
#   Payment Entry-after-submit-debt-closure-check.
#
#   The REPORT replacing it is deliberately not built here: until Group 11 A1
#   fixes the cost basis, any profit figure is wrong, and a report would only
#   present the error more convincingly.
#
# ── D6: small fixes ──────────────────────────────────────────────────
#   Task-before-save-dispatch-gates   Returns restocking now requires a photo;
#                                     stale comment about the disabled
#                                     debt-closure script corrected
#   Dispatch Case                     delete delivery_photo, return_dropoff_photo
#   Property Setter                   delete surgery_set_type-allow_on_submit
#                                     (the field exists nowhere)
#   Task-Action Buttons.js            delete unused tab_is_admin()
#   Dispatch Case-Photo-Galleries.js  stop hiding the deleted fields
#   Task-Account Details UI Cleanup.js  header said Enabled: 0, server says 1
#
#   NOT touched: user_has_allowed_role() in Task-before-save-policy. It looks
#   unused but D3 re-enabled the block that calls it.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy                      (schema deletions are SKIPPED)
#   ... -Mode Deploy -ConfirmDeletions    (schema deletions applied)
# ==============================================================

param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [switch]$ConfirmDeletions
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

$RETIRE = @("Order accepting", "Dispatch picking / hand-off")
$NEWDEFAULT = "Order entry"

Write-Host "D4+D5+D6 cleanup -> $BaseUrl  [Mode=$Mode  ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
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

function Push-Script { param([string]$DocType, [string]$Name, [string]$Rel)
    $path = Join-Path $WorkDir $Rel
    if (-not (Test-Path $path)) { throw "Work file not found: $path" }
    $raw = Read-WorkScript $path
    $doc = Get-ErpDoc $DocType $Name
    if (-not $doc) { throw "$DocType '$Name' does not exist on $BaseUrl." }
    if ((Normalize $raw) -eq (Normalize $doc.script)) {
        Write-Host ("  {0,-44} SAME" -f $Name) -ForegroundColor DarkGray
        return 0
    }
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-44} DIFFERS" -f $Name) -ForegroundColor Yellow
    } else {
        Invoke-Erp Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" @{ script = $raw } | Out-Null
        Write-Host ("  {0,-44} UPDATED" -f $Name) -ForegroundColor Green
    }
    return 1
}

# ── 0. Pre-flight: nothing may be using the kinds we retire ───────────
Write-Host "[0] Pre-flight" -ForegroundColor Magenta
foreach ($k in $RETIRE) {
    $r = Invoke-Erp Get "/api/method/frappe.client.get_count?doctype=Task&filters=$(Enc ('[["task_kind","=","' + $k + '"]]'))"
    $n = [int]$r.message
    if ($n -gt 0) {
        throw "Refusing to retire task_kind '$k': $n Task(s) still use it. Migrate them first."
    }
    Write-Host ("  {0,-44} 0 tasks - safe to retire" -f $k) -ForegroundColor Green
}
Write-Host ""

$changed = 0

# ── 1. D4: task_kind options + default ────────────────────────────────
Write-Host "[1] D4 - task_kind options and default" -ForegroundColor Magenta
$tk = Get-ErpDoc "Custom Field" "Task-task_kind"
if (-not $tk) { throw "Custom Field 'Task-task_kind' not found." }
$opts = ($tk.options -split "`n") | Where-Object { $_ -ne "" }
$kept = $opts | Where-Object { $RETIRE -notcontains $_ }
$removed = $opts | Where-Object { $RETIRE -contains $_ }
Write-Host ("  options: {0} -> {1}   (removing: {2})" -f $opts.Count, $kept.Count, ($removed -join ", ")) -ForegroundColor $(if ($removed.Count) { "Yellow" } else { "DarkGray" })
Write-Host ("  default: '{0}' -> '{1}'" -f $tk.default, $NEWDEFAULT) -ForegroundColor $(if ($tk.default -ne $NEWDEFAULT) { "Yellow" } else { "DarkGray" })
if ($kept -notcontains $NEWDEFAULT) { throw "New default '$NEWDEFAULT' is not in the retained options." }
if ($removed.Count -or $tk.default -ne $NEWDEFAULT) {
    $changed++
    if ($Mode -eq "Deploy") {
        Invoke-Erp Put "/api/resource/$(Enc 'Custom Field')/$(Enc 'Task-task_kind')" @{ options = ($kept -join "`n"); default = $NEWDEFAULT } | Out-Null
        Write-Host "  APPLIED" -ForegroundColor Green
    }
}
Write-Host ""

# ── 2. D5 + D6: schema deletions ──────────────────────────────────────
Write-Host "[2] D5+D6 - schema deletions" -ForegroundColor Magenta
# delivery_photo and return_dropoff_photo are NOT Custom Fields -- they are
# DocFields inside the Dispatch Case custom DocType, so removing them means
# rewriting that DocType's entire fields array. Deliberately NOT done here: both
# are read_only and now referenced by nothing, so they are inert, and a botched
# PUT on the central doctype of this flow costs far more than two dead fields.
# Left as a standalone item with its own script, done in isolation.
$Deletions = @(
    @{ dt = "Custom Field";    name = "Dispatch Case-profit";                         why = "nothing writes it" }
    @{ dt = "Property Setter"; name = "Dispatch Case-surgery_set_type-allow_on_submit"; why = "field exists nowhere" }
)
foreach ($d in $Deletions) {
    $doc = Get-ErpDoc $d.dt $d.name
    if (-not $doc) {
        Write-Host ("  {0,-48} ABSENT" -f $d.name) -ForegroundColor DarkGray
        continue
    }
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-48} WOULD DELETE  ({1})" -f $d.name, $d.why) -ForegroundColor Yellow
    } elseif (-not $ConfirmDeletions) {
        Write-Host ("  {0,-48} SKIPPED - pass -ConfirmDeletions" -f $d.name) -ForegroundColor Yellow
    } else {
        Invoke-Erp Delete "/api/resource/$(Enc $d.dt)/$(Enc $d.name)" | Out-Null
        Write-Host ("  {0,-48} DELETED" -f $d.name) -ForegroundColor Green
        $changed++
    }
}
Write-Host ""

# ── 3. Server Scripts ─────────────────────────────────────────────────
Write-Host "[3] Server Scripts" -ForegroundColor Magenta
# Assert the restock gate is live in code, not just described in a comment.
$gpath = Join-Path $WorkDir "server\Task-before-save-dispatch-gates.py"
$gcode = ((((Read-WorkScript $gpath) -split "`n") | ForEach-Object { ($_ -split "#", 2)[0] }) -join "`n")
if ($gcode -notmatch 'task_kind == "Returns restocking"') {
    throw "Refusing to deploy gates: the Returns restocking gate is not live in code."
}
$changed += Push-Script "Server Script" "Task-before-save-dispatch-gates" "server\Task-before-save-dispatch-gates.py"
$changed += Push-Script "Server Script" "Dispatch-Case-before-save-access-control" "server\Dispatch-Case-before-save-access-control.py"
$changed += Push-Script "Server Script" "Dispatch-Case-before-save-submitted-access-control" "server\Dispatch-Case-before-save-submitted-access-control.py"
Write-Host ""

# ── 4. Client Scripts ─────────────────────────────────────────────────
Write-Host "[4] Client Scripts" -ForegroundColor Magenta
$changed += Push-Script "Client Script" "Task-Field-Visibility" "client\Task-Field-Visibility.js"
$changed += Push-Script "Client Script" "Task-Action Buttons" "client\Task-Action Buttons.js"
$changed += Push-Script "Client Script" "Dispatch Case-Photo-Galleries" "client\Dispatch Case-Photo-Galleries.js"
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "[Check] $changed change(s) pending. Re-run with -Mode Deploy -ConfirmDeletions." -ForegroundColor Cyan
} else {
    Write-Host "[Deploy] $changed change(s) applied." -ForegroundColor Cyan
    if (-not $ConfirmDeletions) {
        Write-Host "NOTE: schema deletions were skipped. Re-run with -ConfirmDeletions to apply them." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Clear cache, then verify:" -ForegroundColor Yellow
    Write-Host "  ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "    `"docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`"" -ForegroundColor DarkGray
    Write-Host "  Get-Content deploy\test\deploy\group-1-dispatch-operational\d4-d6-verify-cleanup.py | ``" -ForegroundColor DarkGray
    Write-Host "    ssh ... `"docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console`"" -ForegroundColor DarkGray
}
