# ==============================================================
# W4 + W5 - Collection episodes, and closure driven by the ledger
# (Group 11 financial tail rebuild)
#
# Deployed together because W5's trigger replaces the half of
# Task-after-save-debt-closure that W4 restructures.
#
# W4 - A Debt Collection task becomes an EPISODE of chasing work
#   A debt task used to be created the instant an invoice was raised, then live
#   forever, accumulating every later invoice for that customer. It could not be
#   completed while anything was owed, so completing it was never truthful.
#   The debt belongs in the ledger; a task is one attempt at collecting it.
#
#   Adds Task.collection_outcome / collection_follow_up_date / collection_note,
#   a Daily scheduler that raises episodes when an invoice is actually overdue
#   (or a threshold is breached, or a promised follow-up date arrives), and a
#   completion gate requiring an outcome.
#
#   Creating the task at invoice time also stopped making sense once W6 applied
#   Net 30 terms: chasing a customer on day zero is noise when they have thirty
#   days to pay. create_or_update_debt_task is therefore removed entirely --
#   the function whose cross-task write caused C1 no longer exists.
#
# W5 - Settlement is a ledger event, so the ledger raises the approval
#   Debt Closure Approval used to be raised when a Debt Collection TASK was
#   completed, conflating "a person finished chasing" with "the customer paid".
#   Two episodes on test were closed still carrying real balances, and an
#   approval was raised anyway.
#
#   Fixes G2: `Closed` was previously reachable only when a case was fully
#   prepaid BEFORE its invoice task completed. For the normal pay-after-invoice
#   flow nothing ever moved the case again -- zero of 270 cases on test had ever
#   been Closed. Payment now closes them.
#
#   Fixes the G10 double count: profit was recomputed on every approval
#   completion by summing EVERY invoice for the customer, so two approvals
#   counted the same invoices twice. It is now computed once, at creation, over
#   exactly the cases that settlement closed -- and a case reaches Closed only
#   once, making that set idempotent by construction.
#
#   Retires Task-after-save-debt-closure entirely.
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

Write-Host "W4+W5 episodes and ledger closure -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

# ── 1. Episode outcome fields ─────────────────────────────────────────
$EpisodeFields = @(
    @{ Name = "Task-collection_outcome"; fieldname = "collection_outcome"; label = "Collection Outcome"
        fieldtype = "Select"; options = "`nPaid`nPromised`nDisputed`nUnreachable`nNo Answer"
        insert_after = "custom_debt_panel"
        description = "What happened on this collection attempt. Required before completing." },
    @{ Name = "Task-collection_follow_up_date"; fieldname = "collection_follow_up_date"; label = "Follow-up Date"
        fieldtype = "Date"; options = ""
        insert_after = "collection_outcome"
        description = "When to try again. The next collection episode is raised on this date. Required when the outcome is Promised." },
    @{ Name = "Task-collection_note"; fieldname = "collection_note"; label = "Collection Note"
        fieldtype = "Small Text"; options = ""
        insert_after = "collection_follow_up_date"
        description = "What was said, who was spoken to, anything the next attempt should know." }
)

Write-Host "[1] Episode outcome fields on Task" -ForegroundColor Magenta
foreach ($f in $EpisodeFields) {
    $existing = Get-ErpDoc "Custom Field" $f.Name
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-28} {1}" -f $f.fieldname, $(if ($existing) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($existing) { "DarkGray" } else { "Yellow" })
    } elseif (-not $existing) {
        $payload = @{
            doctype = "Custom Field"; dt = "Task"; label = $f.label
            fieldname = $f.fieldname; fieldtype = $f.fieldtype
            insert_after = $f.insert_after; description = $f.description
        }
        if ($f.options) { $payload.options = $f.options }
        Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" $payload | Out-Null
        Write-Host ("  {0,-28} CREATED" -f $f.fieldname) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-28} exists" -f $f.fieldname) -ForegroundColor DarkGray
    }
}

# ── 2. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "Scheduled-debt-collection-episodes"; File = "server\Scheduled-debt-collection-episodes.py"; Type = "Scheduler Event"; Freq = "Daily" },
    @{ Name = "Payment Entry-after-submit-debt-closure-check"; File = "server\Payment Entry-after-submit-debt-closure-check.py"; Ref = "Payment Entry"; Event = "After Submit"; Type = "DocType Event" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Task-after-save-dispatch-flow"; File = "server\Task-after-save-dispatch-flow.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" }
)

Write-Host ""
Write-Host "[2] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-46} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-46} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-46} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "Scheduler Event") { $doc.event_frequency = $s.Freq }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-46} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

# ── 3. Retire the old closure script ──────────────────────────────────
Write-Host ""
Write-Host "[3] Retire Task-after-save-debt-closure" -ForegroundColor Magenta
$old = Get-ErpDoc "Server Script" "Task-after-save-debt-closure"
if (-not $old) {
    Write-Host "  not found -- SKIP" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host ("  {0}" -f $(if ($old.disabled -eq 1) { "already disabled" } else { "ENABLED (will disable)" })) -ForegroundColor $(if ($old.disabled -eq 1) { "DarkGray" } else { "Yellow" })
} else {
    $body = Read-WorkScript (Join-Path $WorkDir "server\Task-after-save-debt-closure.py")
    Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc 'Task-after-save-debt-closure')" @{ script = $body; disabled = 1 } | Out-Null
    Write-Host "  DISABLED" -ForegroundColor Green
}

# ── 4. Client scripts ─────────────────────────────────────────────────
$ClientScripts = @(
    @{ Name = "Task-Field-Visibility"; File = "client\Task-Field-Visibility.js" },
    @{ Name = "Task-Field-Editability"; File = "client\Task-Field-Editability.js" }
)

Write-Host ""
Write-Host "[4] Client scripts" -ForegroundColor Magenta
foreach ($c in $ClientScripts) {
    $path = Join-Path $WorkDir $c.File
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Client Script" $c.Name
    if ($Mode -eq "Check") {
        $state = if ($existing -and ([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS" }
        Write-Host ("  {0,-46} {1}" -f $c.Name, $state)
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
        Write-Host ("  {0,-46} UPDATED" -f $c.Name) -ForegroundColor Green
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
