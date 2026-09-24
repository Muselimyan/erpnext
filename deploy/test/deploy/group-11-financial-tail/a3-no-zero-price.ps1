# ==============================================================
# A3 + the zero-price rule: NO ITEM PRICED AT ZERO MAY PARTICIPATE IN THE FLOW.
#
# A3 as originally written was a disagreement between two invoice paths. That
# turned out to be the LAST of nine ways a zero price got in or survived. This
# closes all of them, plus the remaining validation bypasses.
#
# CREATION
#   task_apply_template      resolved no price at all -- every templated line
#                            landed at zero. Now resolves each line through the
#                            same chain as add-product and refuses the WHOLE
#                            template if any line is unpriced (a kit applied
#                            half-priced is worse than one refused).
#   Products Button (client) wrote Item.standard_rate || 0, from a field
#                            populated on no items, so it produced a zero-priced
#                            row every time. DISABLED.
#   Template Auto Fill (js)  built case_items in the browser with no price.
#                            DISABLED; task_apply_template does it properly and
#                            is already wired to the Task UI.
#
# DISCOUNT
#   0 <= discount_pct < 100, enforced on add AND update. 100% is not a discount
#   but a giveaway, and it produced a line that could be neither invoiced nor
#   written off. Negative discounts refused too -- that is a price rise by the
#   back door, and prices come from the price list or a tender.
#
# GATES
#   Dispatch-Case-before-submit gains the backstop check on the EFFECTIVE rate
#   (unit_price x (1 - discount/100)), because it is the only price gate that
#   cannot be stepped around: the order-entry gate is skipped once the case is
#   submitted, and Discount Approval re-submits without re-checking.
#   The order-entry gate is corrected from unit_price to the effective rate.
#
# CONSUMERS
#   task_close_case_nothing_to_invoice tested raw unit_price while
#   task_commit_invoice tested the effective rate, and they disagreed in BOTH
#   directions: a zero-priced consumed row closed with no invoice (silent
#   revenue loss), and a 100%-discount row was refused by both (unfinishable
#   task). Both now use the effective rate.
#
# POST-SUBMIT
#   unit_price and discount_pct were allow_on_submit via Property Setters, so a
#   price could be zeroed AFTER the case was submitted, bypassing discount
#   approval entirely. Those two setters are removed. Verified safe: no server
#   code writes either field on a submitted case -- both product endpoints are
#   hard-gated to docstatus 0.
#
# BYPASS FLAGS
#   ignore_validate_update_after_submit removed from all four packing/returns
#   endpoints. Nine of the ten fields they write were already allow_on_submit;
#   the flag was covering for ONE that was not (lost_damaged_presence), which is
#   corrected here instead. ignore_mandatory in task_create_dispatch_case is
#   KEPT and justified in a comment -- it is the empty shell an order is built
#   into, and mandatory fields are enforced where the order becomes real.
#
# OVERRIDE ENDPOINTS
#   disable_all_item_batch_serial_for_now and perm_disable_batch_expiry_dbset
#   are whitelisted, unauthenticated, and strip traceability flags from every
#   Item. Disabled here. Deletion belongs with the batching workstream.
#
# ORDER MATTERS: lost_damaged_presence must become allow_on_submit BEFORE the
# scripts that drop the bypass flag are deployed, or returns processing breaks
# between the two steps.
#
# TEST ONLY.
#   ... -Mode Check
#   ... -Mode Deploy -ConfirmDeletions
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

Write-Host "A3 no zero price -> $BaseUrl  [Mode=$Mode  ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
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
        return (($wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")) | ConvertFrom-Json).data
    } catch { return $null }
}
function Read-WorkScript { param([string]$Path)
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}
function Get-Code { param([string]$Body, [string]$CommentToken)
    return (($Body -split "`n" | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($CommentToken)) }) -join "`n")
}

# ── 1. Assert the fixes are in executable code, not in the comments ───
Write-Host "[1] Assert each fix is live code" -ForegroundColor Magenta
$tmplCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_apply_template.py")) "#"
if ($tmplCode -notmatch 'unpriced_items') { throw "A.1: task_apply_template has no unpriced refusal in live code." }
if ($tmplCode -notmatch '"unit_price"') { throw "A.1: task_apply_template still appends rows without a unit_price." }
Write-Host "  A.1 template resolves and refuses" -ForegroundColor Green

foreach ($pair in @(@("task_add_dispatch_product.py", "add"), @("task_update_dispatch_product.py", "update"))) {
    $c = Get-Code (Read-WorkScript (Join-Path $WorkDir ("server\" + $pair[0]))) "#"
    if ($c -notmatch '>=\s*100') { throw ("A.2: no 100% discount bound in " + $pair[0]) }
    if ($c -notmatch '<\s*0') { throw ("A.2: no negative discount bound in " + $pair[0]) }
}
Write-Host "  A.2 discount bounded on add and update" -ForegroundColor Green

$subCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\Dispatch-Case-before-submit.py")) "#"
if ($subCode -notmatch 'discount_pct') { throw "A.3: submit gate does not consider discount_pct." }
if ($subCode -notmatch 'unpriced_lines') { throw "A.3: submit gate has no zero-price refusal." }
Write-Host "  A.3 submit backstop present" -ForegroundColor Green

$gateCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\Task-before-save-dispatch-gates.py")) "#"
if ($gateCode -notmatch 'row_rate') { throw "A.3: order-entry gate still checks unit_price alone." }
Write-Host "  A.3 order-entry gate uses the effective rate" -ForegroundColor Green

$closeCode = Get-Code (Read-WorkScript (Join-Path $WorkDir "server\task_close_case_nothing_to_invoice.py")) "#"
if ($closeCode -notmatch 'r_rate') { throw "A.5: nothing-to-invoice still tests raw unit_price." }
Write-Host "  A.5 consumers agree on billable" -ForegroundColor Green

foreach ($f in @("task_mark_item_packed.py", "task_mark_items_packed_batch.py", "dispatch_case_packing_scan.py", "task_update_return_item_quantities.py")) {
    $c = Get-Code (Read-WorkScript (Join-Path $WorkDir ("server\" + $f))) "#"
    if ($c -match 'ignore_validate_update_after_submit') { throw ("A.6: bypass flag still live in " + $f) }
}
Write-Host "  A.6 bypass flag gone from all four endpoints" -ForegroundColor Green
Write-Host ""

# ── 2. SCHEMA FIRST: lost_damaged_presence must allow_on_submit ───────
# Before the scripts that no longer bypass the check are deployed, or returns
# processing breaks in the window between the two.
Write-Host "[2] Schema: lost_damaged_presence allow_on_submit" -ForegroundColor Magenta
$cfName = "Dispatch Case Item-lost_damaged_presence"
$cf = Get-ErpDoc "Custom Field" $cfName
if (-not $cf) {
    $cf = Get-ErpDoc "Custom Field" "lost_damaged_presence"
    if ($cf) { $cfName = $cf.name }
}
if (-not $cf) {
    throw "Could not find the lost_damaged_presence Custom Field. It must be allow_on_submit before the bypass removal is safe."
}
if ([int]$cf.allow_on_submit -eq 1) {
    Write-Host "  already allow_on_submit" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  allow_on_submit=0 - WOULD SET to 1" -ForegroundColor Yellow
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Custom Field')/$(Enc $cfName)" @{ allow_on_submit = 1 } | Out-Null
    Write-Host "  allow_on_submit SET to 1" -ForegroundColor Green
}
Write-Host ""

# ── 3. Scripts ────────────────────────────────────────────────────────
$Server = @(
    "task_apply_template", "task_add_dispatch_product", "task_update_dispatch_product",
    "Dispatch-Case-before-submit", "Task-before-save-dispatch-gates",
    "task_close_case_nothing_to_invoice", "task_create_dispatch_case",
    "task_mark_item_packed", "task_mark_items_packed_batch",
    "dispatch_case_packing_scan", "task_update_return_item_quantities"
)
Write-Host "[3] Server scripts" -ForegroundColor Magenta
foreach ($n in $Server) {
    $p = Join-Path $WorkDir ("server\" + $n + ".py")
    if (-not (Test-Path $p)) { throw "Missing work file: $p" }
    $b = Read-WorkScript $p
    $e = Get-ErpDoc "Server Script" $n
    if (-not $e) { Write-Host ("  {0,-40} MISSING ON SERVER" -f $n) -ForegroundColor Red; continue }
    $same = ($e.script -replace "`r`n", "`n").TrimEnd() -eq ($b -replace "`r`n", "`n").TrimEnd()
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-40} {1}" -f $n, $(if ($same) { "identical" } else { "DIFFERS" })) -ForegroundColor $(if ($same) { "DarkGray" } else { "Yellow" })
    } elseif ($same) {
        Write-Host ("  {0,-40} identical" -f $n) -ForegroundColor DarkGray
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $n)" @{ script = $b } | Out-Null
        Write-Host ("  {0,-40} UPDATED" -f $n) -ForegroundColor Green
    }
}
Write-Host ""

# ── 4. Client scripts to disable ──────────────────────────────────────
Write-Host "[4] Client scripts (disabling the zero-price paths)" -ForegroundColor Magenta
foreach ($n in @("Dispatch Case-Products Button", "Dispatch Case-Template Auto Fill")) {
    $p = Join-Path $WorkDir ("client\" + $n + ".js")
    $b = Read-WorkScript $p
    $e = Get-ErpDoc "Client Script" $n
    if (-not $e) { Write-Host ("  {0,-38} MISSING ON SERVER" -f $n) -ForegroundColor Red; continue }
    $needsDisable = [int]$e.enabled -eq 1
    $sameBody = ($e.script -replace "`r`n", "`n").TrimEnd() -eq ($b -replace "`r`n", "`n").TrimEnd()
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-38} enabled={1} body={2}" -f $n, $e.enabled, $(if ($sameBody) { "identical" } else { "DIFFERS" })) -ForegroundColor $(if ($needsDisable -or -not $sameBody) { "Yellow" } else { "DarkGray" })
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $n)" @{ script = $b; enabled = 0 } | Out-Null
        Write-Host ("  {0,-38} UPDATED + DISABLED" -f $n) -ForegroundColor Green
    }
}
Write-Host ""

# ── 5. Property setters: price is not editable after submit ───────────
Write-Host "[5] Remove allow_on_submit from unit_price and discount_pct" -ForegroundColor Magenta
$SnapDir = Join-Path $PSScriptRoot "snapshots"
if (-not (Test-Path $SnapDir)) { New-Item -ItemType Directory -Path $SnapDir | Out-Null }
foreach ($fld in @("unit_price", "discount_pct")) {
    $psName = "Dispatch Case Item-" + $fld + "-allow_on_submit"
    $ps = Get-ErpDoc "Property Setter" $psName
    if (-not $ps) {
        Write-Host ("  {0,-16} no allow_on_submit setter (already locked)" -f $fld) -ForegroundColor DarkGray
        continue
    }
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-16} setter value={1} - WOULD DELETE (needs -ConfirmDeletions)" -f $fld, $ps.value) -ForegroundColor Yellow
    } elseif (-not $ConfirmDeletions) {
        Write-Host ("  {0,-16} SKIPPED - pass -ConfirmDeletions" -f $fld) -ForegroundColor Yellow
    } else {
        $snap = Join-Path $SnapDir ("a3-propsetter-" + $fld + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
        [System.IO.File]::WriteAllText($snap, ($ps | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        Invoke-Erp Delete "/api/resource/$(Enc 'Property Setter')/$(Enc $psName)" | Out-Null
        Write-Host ("  {0,-16} DELETED (snapshot saved)" -f $fld) -ForegroundColor Green
    }
}
Write-Host ""

# ── 6. Disable the unauthenticated override endpoints ─────────────────
Write-Host "[6] Disable pre-launch override endpoints" -ForegroundColor Magenta
foreach ($n in @("disable_all_item_batch_serial_for_now", "perm_disable_batch_expiry_dbset")) {
    $e = Get-ErpDoc "Server Script" $n
    if (-not $e) { Write-Host ("  {0,-42} not present" -f $n) -ForegroundColor DarkGray; continue }
    if ([int]$e.disabled -eq 1) {
        Write-Host ("  {0,-42} already disabled" -f $n) -ForegroundColor DarkGray
    } elseif ($Mode -eq "Check") {
        Write-Host ("  {0,-42} ENABLED - would disable" -f $n) -ForegroundColor Yellow
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $n)" @{ disabled = 1 } | Out-Null
        Write-Host ("  {0,-42} DISABLED" -f $n) -ForegroundColor Green
    }
}
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy -ConfirmDeletions." -ForegroundColor Yellow
} else {
    Write-Host "[Deploy] done. Now:" -ForegroundColor Cyan
    Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  a3-verify-no-zero-price.py, then the full regression set" -ForegroundColor DarkGray
}
