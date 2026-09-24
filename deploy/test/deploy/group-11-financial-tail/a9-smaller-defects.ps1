# ==============================================================
# A9 - five defects, of which two were one causal chain.
#
# C.1  DUPLICATE ACTIVE TENDERS ARE REFUSED AT ORDER ENTRY.
#      The tender loop in task_add_dispatch_product had no break and no
#      order_by, so with two active tenders on one item the LAST one scanned
#      won -- from an unordered query, so the price a client got was not even
#      deterministic. The collision was caught much later by the Sales Invoice
#      validator, which throws on submit: after the order had been picked,
#      delivered and returned. Now refused where the item is chosen, with the
#      validator's own wording. Fixed in task_update_dispatch_product too,
#      which re-resolves price on every line change -- fixing only the add
#      path would have moved the hole, not closed it.
#
# C.2  A STRANDED DRAFT NO LONGER DEADLOCKS THE CASE.
#      When the validator above threw inside si.submit(), the inserted draft
#      remained. The idempotency guard matches docstatus != 2, so it matched
#      that draft and every retry said "already has invoice ... Cancel it
#      first" -- a draft cannot be cancelled, only deleted. Meanwhile
#      Task-before-save-dispatch-gates refused to complete the task while the
#      draft existed, and told the user to submit it by hand. Two errors
#      pointing at each other, neither actionable.
#      Now: a SUBMITTED invoice still blocks and says so; a DRAFT is debris
#      from a failed attempt, so it is deleted and the commit proceeds. The
#      gate's message now sends the user back to the action instead of to the
#      Sales Invoice form.
#
# C.3  TENDER DATA CAN NO LONGER MAKE AN INVOICE UNCANCELLABLE.
#      The reversal ran on After Cancel, where a throw rolls back the
#      cancellation. A deleted tender, or a deleted tender item row, threw --
#      so a data problem in a DIFFERENT document permanently blocked cancelling
#      the invoice. Failing to return quantity is the smaller harm and a human
#      can correct it on the tender, so unreversible rows are now logged and
#      skipped and the cancel proceeds.
#
# C.4  A SETTLEMENT ALWAYS GETS DIRECTOR REVIEW (O3).
#      The approval was raised only when the payment itself closed a case. If
#      every case was already Closed, or a case sat outside Payment Pending /
#      Invoice Pending, the balance reached zero with no Director seeing it and
#      no profit recorded. Now raised either way. When nothing closed, the
#      description says so explicitly rather than printing "Profit: 0", which
#      would read as a computed figure; custom_case_profit is left blank for
#      the same reason. Also fixes a latent IndexError on closed_cases[0] that
#      this branch would have hit the moment it became reachable.
#
# C.5  DEBT PANEL N+1 REMOVED. One query for all allocations, bucketed, instead
#      of one per payment row (up to 51 for a 50-row screen).
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

Write-Host "A9 smaller defects -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

$Scripts = @(
    @{ Name = "task_add_dispatch_product"; File = "server\task_add_dispatch_product.py" },
    @{ Name = "task_update_dispatch_product"; File = "server\task_update_dispatch_product.py" },
    @{ Name = "task_commit_invoice"; File = "server\task_commit_invoice.py" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py" },
    @{ Name = "Sales-Invoice-on-cancel-tender-reversal"; File = "server\Sales-Invoice-on-cancel-tender-reversal.py" },
    @{ Name = "Payment Entry-after-submit-debt-closure-check"; File = "server\Payment Entry-after-submit-debt-closure-check.py" },
    @{ Name = "task_debt_panel"; File = "server\task_debt_panel.py" }
)

# ── Assert the fixes are in live code, not in the comments describing them ──
Write-Host "[1] Assert each fix is present in executable code" -ForegroundColor Magenta
function Get-Code { param([string]$Body)
    return (($Body -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}

$addCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_add_dispatch_product.py"))
if ($addCode -notmatch 'len\(tender_matches\)\s*>\s*1') { throw "C.1: duplicate-tender refusal not found in task_add_dispatch_product live code." }
if ($addCode -notmatch 'order_by') { throw "C.1: tender query has no order_by in task_add_dispatch_product." }
Write-Host "  C.1 add: duplicate refused + deterministic order" -ForegroundColor Green

$updCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_update_dispatch_product.py"))
if ($updCode -notmatch 'len\(tender_matches\)\s*>\s*1') { throw "C.1: duplicate-tender refusal not found in task_update_dispatch_product live code." }
Write-Host "  C.1 update: duplicate refused" -ForegroundColor Green

$invCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_commit_invoice.py"))
if ($invCode -notmatch 'submitted_existing') { throw "C.2: submitted/draft split not found in task_commit_invoice live code." }
if ($invCode -notmatch 'delete_doc') { throw "C.2: stranded-draft deletion not found in task_commit_invoice live code." }
Write-Host "  C.2 commit: submitted blocks, draft is cleared" -ForegroundColor Green

$revCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\Sales-Invoice-on-cancel-tender-reversal.py"))
if ($revCode -match 'frappe\.throw') { throw "C.3: Sales-Invoice-on-cancel-tender-reversal still contains a throw. An After Cancel throw rolls back the cancellation." }
if ($revCode -notmatch 'frappe\.db\.exists') { throw "C.3: missing-tender guard not found." }
Write-Host "  C.3 reversal: cannot throw, tender existence guarded" -ForegroundColor Green

$setCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\Payment Entry-after-submit-debt-closure-check.py"))
if ($setCode -match 'elif not closed_cases') { throw "C.4: the no-approval branch is still present." }
if ($setCode -notmatch 'closed_cases\[0\] if closed_cases else') { throw "C.4: unguarded closed_cases[0] still present." }
Write-Host "  C.4 settlement: approval always raised, index guarded" -ForegroundColor Green

$pnlCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_debt_panel.py"))
if ($pnlCode -notmatch 'alloc_by_parent') { throw "C.5: bucketed allocation lookup not found." }
if ($pnlCode -match '"parent"\s*:\s*pe\.name') { throw "C.5: per-row allocation query is still present." }
Write-Host "  C.5 panel: single bucketed allocation query" -ForegroundColor Green
Write-Host ""

# ── Deploy ────────────────────────────────────────────────────────────
Write-Host "[2] Server scripts" -ForegroundColor Magenta
foreach ($s in $Scripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { throw "Missing work file: $path" }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if (-not $existing) { Write-Host ("  {0,-46} MISSING ON SERVER" -f $s.Name) -ForegroundColor Red; continue }
    $same = ($existing.script -replace "`r`n", "`n").TrimEnd() -eq ($body -replace "`r`n", "`n").TrimEnd()
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-46} {1}" -f $s.Name, $(if ($same) { "identical" } else { "DIFFERS" })) -ForegroundColor $(if ($same) { "DarkGray" } else { "Yellow" })
    } elseif ($same) {
        Write-Host ("  {0,-46} identical" -f $s.Name) -ForegroundColor DarkGray
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body } | Out-Null
        Write-Host ("  {0,-46} UPDATED" -f $s.Name) -ForegroundColor Green
    }
}
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Yellow
} else {
    Write-Host "[Deploy] done. Now run:" -ForegroundColor Cyan
    Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  then a9-verify-smaller-defects.py, then re-run w6 / w4-w5 / e2e-full-chain" -ForegroundColor DarkGray
}
