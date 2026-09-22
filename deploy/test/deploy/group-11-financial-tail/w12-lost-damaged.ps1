# ==============================================================
# W12 - Lost & Damaged resolution path (Group 11, item A3)
#
# lost_damaged_qty was captured at returns inspection and then nothing happened
# to it. The return pickup moves the full DISPATCHED quantity back, so Returns
# receives everything and only used and returned leave -- the lost/damaged
# remainder was stranded there indefinitely, mixed in with good sellable
# returns and indistinguishable from them.
#
# Now: the units are segregated into their own warehouse at inspection, a
# Director decides whether to bill the client or write them off, and either
# outcome empties that warehouse.
#
# Creates:
#   Warehouse     Lost & Damaged - Inmed
#   Custom Field  Dispatch Case Item.lost_damaged_presence  (Select)
#   Custom Field  Task.writeoff_outcome                     (Select)
#   Custom Field  Sales Invoice.source_task                 (Link -> Task)
#   Custom Field  Stock Entry.source_task                    (Link -> Task)
#
# Updates:
#   Task-after-save-dispatch-flow       segregation transfer, approval task,
#                                       resolution handler, create_se gains an
#                                       expense_account parameter
#   Task-before-save-dispatch-gates     presence required at inspection;
#                                       outcome required at approval
#   task_update_return_item_quantities  accepts and validates the presence
#   task_commit_invoice                 idempotency re-keyed so a case can carry
#                                       both a used-items and a lost/damaged
#                                       invoice without either double-billing
#   Task-Product Work Area              presence selector in all three returns
#                                       layouts; presence shown on the invoice
#                                       preview
#   Task-Field-Visibility / -Editability
#   Dispatch Case-Simplify for Order Creation
#
# Write-offs post to Stock Adjustment - Inmed, NOT Cost of Goods Sold: these
# units were never sold, and routing them through COGS would distort the gross
# margin on real sales -- the very figures item A1 exists to make trustworthy.
#
# A write-off REFUSES un-valued stock. It is the one operation whose entire
# purpose is the GL amount, so item A2's allow_zero_valuation_rate would have it
# book a zero-value loss and report success -- recognising nothing while looking
# like it worked. Checked explicitly against the bin, because create_se also sets
# ignore_validate and that skips ERPNext's own check.
#
# KNOWN LIMIT: that carve-out covers the write-off branch only. A2 is still open
# everywhere else, including the segregation transfer and the billed-out issue,
# so those can still post movements whose value is not trustworthy.
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

$LD_WH = "Lost & Damaged - Inmed"

Write-Host "W12 lost & damaged -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    # Explicit UTF-8 decode -- Invoke-RestMethod decodes responses as Latin-1
    # when no charset is declared, producing false "DIFFERS" for non-ASCII.
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    # -Encoding UTF8 is REQUIRED: PowerShell 5.1 reads BOM-less files as ANSI,
    # mangling non-ASCII before upload.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── 0. Pre-flight ─────────────────────────────────────────────────────
# The approval task is assigned from Task Access Policy.default_team_user. If
# that is blank the flow would create a ToDo with no allocated_to -- a task
# nobody is assigned and nobody sees. The policy record existed when last
# checked, but that is configuration rather than code, and A3 is the first thing
# to depend on it. Fail here rather than on the first real loss.
Write-Host "[0] Pre-flight" -ForegroundColor Magenta
$Policy = Get-ErpDoc "Task Access Policy" "Write-off Approval"
if (-not $Policy) {
    throw "Task Access Policy 'Write-off Approval' does not exist. The approval task cannot be assigned; create the policy before deploying A3."
}
if (-not $Policy.default_team_user) {
    throw "Task Access Policy 'Write-off Approval' has no default_team_user. The approval task would be created unassigned and invisible. Set it before deploying A3."
}
Write-Host ("  {0,-28} {1}" -f "Write-off Approval policy", $Policy.default_team_user) -ForegroundColor DarkGray
Write-Host ""

# ── 1. Warehouse ──────────────────────────────────────────────────────
Write-Host "[1] Warehouse" -ForegroundColor Magenta
$existingWh = Get-ErpDoc "Warehouse" $LD_WH
if ($Mode -eq "Check") {
    Write-Host ("  {0,-28} {1}" -f $LD_WH, $(if ($existingWh) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($existingWh) { "DarkGray" } else { "Yellow" })
} elseif (-not $existingWh) {
    # Mirror the parent of the existing operational warehouses rather than
    # guessing a group name.
    $parent = $null
    $mainWh = Get-ErpDoc "Warehouse" "Main - Inmed"
    if ($mainWh) { $parent = $mainWh.parent_warehouse }
    $payload = @{
        doctype = "Warehouse"; warehouse_name = "Lost & Damaged"; company = "InMED"; is_group = 0
    }
    if ($parent) { $payload.parent_warehouse = $parent }
    Invoke-Erp Post "/api/resource/Warehouse" $payload | Out-Null
    Write-Host ("  {0,-28} CREATED (parent: {1})" -f $LD_WH, $(if ($parent) { $parent } else { "none" })) -ForegroundColor Green
} else {
    Write-Host ("  {0,-28} exists" -f $LD_WH) -ForegroundColor DarkGray
}

# ── 2. Custom fields ──────────────────────────────────────────────────
$Fields = @(
    @{ Name = "Dispatch Case Item-lost_damaged_presence"; dt = "Dispatch Case Item"
        fieldname = "lost_damaged_presence"; label = "Lost or Damaged?"; fieldtype = "Select"
        options = "`nDamaged - in hand`nLost - not recoverable"; insert_after = "lost_damaged_qty"
        description = "Whether the unit physically exists. Damaged units can be scrapped or claimed from the supplier; lost units cannot. Required whenever a lost/damaged quantity is recorded." },
    @{ Name = "Task-writeoff_outcome"; dt = "Task"
        fieldname = "writeoff_outcome"; label = "Write-off Outcome"; fieldtype = "Select"
        options = "`nBill Client`nWrite Off"; insert_after = "approval_note"
        description = "What happens to the held lost/damaged units. Completing the task acts on this: Bill Client raises an invoice, Write Off absorbs the loss. Either way the stock leaves Lost & Damaged." },
    @{ Name = "Sales Invoice-source_task"; dt = "Sales Invoice"
        fieldname = "source_task"; label = "Raised From Task"; fieldtype = "Link"; options = "Task"
        insert_after = "dispatch_case"
        description = "Set only on an invoice raised by a Write-off Approval. Empty means this is the case's used-items invoice. Gives each kind its own idempotency guard." },
    @{ Name = "Stock Entry-source_task"; dt = "Stock Entry"
        fieldname = "source_task"; label = "Raised From Task"; fieldtype = "Link"; options = "Task"
        insert_after = "stock_entry_type"
        description = "The Task whose completion produced this movement. Nothing previously connected a Stock Entry back to the work that caused it; the lost/damaged resolution also uses it as its idempotency key." }
)

Write-Host ""
Write-Host "[2] Custom fields" -ForegroundColor Magenta
foreach ($f in $Fields) {
    $existing = Get-ErpDoc "Custom Field" $f.Name
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-46} {1}" -f $f.Name, $(if ($existing) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($existing) { "DarkGray" } else { "Yellow" })
    } elseif (-not $existing) {
        $payload = @{
            doctype = "Custom Field"; dt = $f.dt; label = $f.label; fieldname = $f.fieldname
            fieldtype = $f.fieldtype; insert_after = $f.insert_after; description = $f.description
        }
        if ($f.options) { $payload.options = $f.options }
        if ($f.fieldname -eq "source_task") { $payload.read_only = 1 }
        Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" $payload | Out-Null
        Write-Host ("  {0,-46} CREATED" -f $f.Name) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-46} exists" -f $f.Name) -ForegroundColor DarkGray
    }
}

# ── 3. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "Task-after-save-dispatch-flow"; File = "server\Task-after-save-dispatch-flow.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "task_update_return_item_quantities"; File = "server\task_update_return_item_quantities.py"; Type = "API" },
    @{ Name = "task_commit_invoice"; File = "server\task_commit_invoice.py"; Type = "API" }
)

Write-Host ""
Write-Host "[3] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-38} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-38} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-38} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "API") { $doc.api_method = $s.Name }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-38} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

# ── 4. Client scripts ─────────────────────────────────────────────────
$ClientScripts = @(
    @{ Name = "Task-Product Work Area"; File = "client\Task-Product Work Area.js"; dt = "Task" },
    @{ Name = "Task-Field-Visibility"; File = "client\Task-Field-Visibility.js"; dt = "Task" },
    @{ Name = "Task-Field-Editability"; File = "client\Task-Field-Editability.js"; dt = "Task" },
    @{ Name = "Dispatch Case-Simplify for Order Creation"; File = "client\Dispatch Case-Simplify for Order Creation.js"; dt = "Dispatch Case" }
)

Write-Host ""
Write-Host "[4] Client scripts" -ForegroundColor Magenta
foreach ($c in $ClientScripts) {
    $path = Join-Path $WorkDir $c.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($c.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Client Script" $c.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-46} {1}" -f $c.Name, $state)
        } else {
            Write-Host ("  {0,-46} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-46} UPDATED" -f $c.Name) -ForegroundColor Green
        } else {
            Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = $c.dt; view = "Form"; script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-46} CREATED" -f $c.Name) -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
    Write-Host "Then:     w12-verify-lost-damaged.py, and re-run the other w*-verify-*.py suites" -ForegroundColor Yellow
}
