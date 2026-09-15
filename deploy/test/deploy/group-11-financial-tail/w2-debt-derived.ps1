# ==============================================================
# W2 - Debt becomes derived (Group 11 financial tail rebuild)
#
# Stops storing receivables on the Task and reads them from the ledger instead.
# The stored copy drifted: Dispatch Cases showed millions outstanding against
# invoices the ledger reported as fully paid, and two Debt Collection tasks were
# closed while still carrying real outstanding balances.
#
# Adds:
#   Task.custom_debt_panel (HTML)     - live rendered debt position
#   task_debt_panel (API)             - computes it from the ledger
#   Task-Debt-Panel.js (Client)       - renders it
#
# Updates:
#   Task-after-save-dispatch-flow     - create_or_update_debt_task stores nothing
#   Task-before-save-payment-recording- allocates against live invoices
#   Task-after-save-debt-closure      - sources invoices/payments from the ledger
#   Task-after-save-advance-payment   - SUBMITS the Payment Entry (G3)
#   Task-before-save-access-control   - debt fields removed from SYSTEM_FIELDS
#   Task-Field-Visibility / -Editability
#
# Deletes (ONLY with -Mode Deploy -ConfirmDeletions):
#   Task fields: open_invoices, payment_history, total_outstanding,
#                available_advance_credit, custom_total_amount_paid
#   Child doctypes: Debt Collection Invoice, Debt Collection Payment
#   Property Setters for the deleted fields
#
# Deletions are gated behind an explicit switch because they are irreversible in
# effect. Run w0-capture-pre-deletion-state.ps1 first.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy                      (code only, no deletions)
#   ... -Mode Deploy -ConfirmDeletions     (code + schema deletions)
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

Write-Host "W2 debt derived -> $BaseUrl  [Mode=$Mode, ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    # Explicit UTF-8 decode: Invoke-RestMethod decodes the response as Latin-1
    # when the server declares no charset, which inflates multi-byte characters
    # and makes Check report a false "DIFFERS" for any script with non-ASCII.
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
    # which mangles non-ASCII before upload. This is the mechanism behind the
    # existing mojibake in Task-after-save-debt-closure's comments.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── 1. New Task field: custom_debt_panel ──────────────────────────────
$DebtPanelField = @{
    doctype     = "Custom Field"
    name        = "Task-custom_debt_panel"
    dt          = "Task"
    label       = "Debt Position"
    fieldname   = "custom_debt_panel"
    fieldtype   = "HTML"
    insert_after = "custom_case_profit"
    read_only   = 1
}

Write-Host "[1] Task field custom_debt_panel" -ForegroundColor Magenta
$existingField = Get-ErpDoc "Custom Field" "Task-custom_debt_panel"
if ($Mode -eq "Check") {
    if ($existingField) { Write-Host "  exists" } else { Write-Host "  WOULD CREATE" -ForegroundColor Yellow }
} else {
    if ($existingField) {
        Invoke-Erp Put "/api/resource/$(Enc 'Custom Field')/$(Enc 'Task-custom_debt_panel')" @{ label = $DebtPanelField.label; read_only = 1 } | Out-Null
        Write-Host "  UPDATED" -ForegroundColor Green
    } else {
        Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" $DebtPanelField | Out-Null
        Write-Host "  CREATED" -ForegroundColor Green
    }
}

# ── 2. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "task_debt_panel"; File = "server\task_debt_panel.py"; Type = "API" },
    @{ Name = "Task-after-save-dispatch-flow"; File = "server\Task-after-save-dispatch-flow.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-payment-recording"; File = "server\Task-before-save-payment-recording.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Task-after-save-debt-closure"; File = "server\Task-after-save-debt-closure.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-after-save-advance-payment"; File = "server\Task-after-save-advance-payment.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-access-control"; File = "server\Task-before-save-access-control.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" }
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
            Write-Host ("  {0,-40} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-40} WOULD CREATE ({1} chars)" -f $s.Name, $body.Length) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-40} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "API") { $doc.api_method = $s.Name }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-40} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

# ── 3. Client scripts ─────────────────────────────────────────────────
$ClientScripts = @(
    @{ Name = "Task-Debt-Panel"; File = "client\Task-Debt-Panel.js" },
    @{ Name = "Task-Field-Visibility"; File = "client\Task-Field-Visibility.js" },
    @{ Name = "Task-Field-Editability"; File = "client\Task-Field-Editability.js" }
)

Write-Host ""
Write-Host "[3] Client scripts" -ForegroundColor Magenta
foreach ($c in $ClientScripts) {
    $path = Join-Path $WorkDir $c.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($c.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Client Script" $c.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-40} {1}" -f $c.Name, $state)
        } else {
            Write-Host ("  {0,-40} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-40} UPDATED" -f $c.Name) -ForegroundColor Green
        } else {
            Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = "Task"; view = "Form"; script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-40} CREATED" -f $c.Name) -ForegroundColor Green
        }
    }
}

# ── 4. Accounting read permissions for the Ops roles ─────────────────
# Ops - Finance had create rights on Payment Entry but NO permission on
# Account, so validating the paid_to / paid_from link fields failed with
# "Insufficient Permission for Account". Recording a payment was therefore
# impossible for the role that owns the task -- every Payment Entry on test was
# created by a System Manager or Administrator, which is why it went unnoticed.
# Same class of defect as C1: it worked for privileged users only.
$PermDocTypes = @("Account", "Mode of Payment", "Cost Center", "Currency", "Company")
$PermRoles = @("Ops - Finance", "Ops - Accounting")

Write-Host ""
Write-Host "[4] Accounting read permissions" -ForegroundColor Magenta
foreach ($dt in $PermDocTypes) {
    foreach ($r in $PermRoles) {
        $has = $false
        try {
            $q = "/api/resource/$(Enc 'Custom DocPerm')?limit_page_length=1&filters=" + (Enc ('{"parent":["=","' + $dt + '"],"role":["=","' + $r + '"],"permlevel":["=",0]}'))
            $rows = (Invoke-Erp Get $q).data
            if ($rows -and @($rows).Count -gt 0) { $has = $true }
        } catch {}
        if ($Mode -eq "Check") {
            Write-Host ("  {0,-18} -> {1,-18} {2}" -f $dt, $r, $(if ($has) { "present" } else { "WOULD GRANT read" })) -ForegroundColor $(if ($has) { "DarkGray" } else { "Yellow" })
        } elseif (-not $has) {
            Invoke-Erp Post "/api/resource/$(Enc 'Custom DocPerm')" @{
                doctype = "Custom DocPerm"; parent = $dt; parenttype = "DocType"
                parentfield = "permissions"; role = $r; permlevel = 0; read = 1
            } | Out-Null
            Write-Host ("  {0,-18} -> {1,-18} GRANTED read" -f $dt, $r) -ForegroundColor Green
        } else {
            Write-Host ("  {0,-18} -> {1,-18} present" -f $dt, $r) -ForegroundColor DarkGray
        }
    }
}

# ── 5. Schema deletions ───────────────────────────────────────────────
$DeleteCustomFields = @(
    "Task-open_invoices",
    "Task-payment_history",
    "Task-total_outstanding",
    "Task-available_advance_credit",
    "Task-custom_total_amount_paid"
)
$DeletePropertySetters = @(
    "Task-open_invoices-depends_on",
    "Task-payment_history-depends_on",
    "Task-total_outstanding-depends_on",
    "Task-available_advance_credit-depends_on"
)
$DeleteDocTypes = @(
    "Debt Collection Invoice",
    "Debt Collection Payment"
)

Write-Host ""
Write-Host "[5] Schema deletions" -ForegroundColor Magenta
if ($Mode -eq "Check" -or -not $ConfirmDeletions) {
    foreach ($n in $DeleteCustomFields) {
        $e = Get-ErpDoc "Custom Field" $n
        Write-Host ("  Custom Field     {0,-34} {1}" -f $n, $(if ($e) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($e) { "Yellow" } else { "DarkGray" })
    }
    foreach ($n in $DeletePropertySetters) {
        $e = Get-ErpDoc "Property Setter" $n
        Write-Host ("  Property Setter  {0,-34} {1}" -f $n, $(if ($e) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($e) { "Yellow" } else { "DarkGray" })
    }
    foreach ($n in $DeleteDocTypes) {
        $e = Get-ErpDoc "DocType" $n
        Write-Host ("  DocType          {0,-34} {1}" -f $n, $(if ($e) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($e) { "Yellow" } else { "DarkGray" })
    }
    if ($Mode -eq "Deploy") {
        Write-Host "  (skipped: pass -ConfirmDeletions to apply)" -ForegroundColor Yellow
    }
} else {
    # Order matters: Custom Fields and Property Setters referencing the child
    # doctypes must go before the doctypes themselves.
    foreach ($n in $DeletePropertySetters) {
        if (Get-ErpDoc "Property Setter" $n) {
            Invoke-Erp Delete "/api/resource/$(Enc 'Property Setter')/$(Enc $n)" | Out-Null
            Write-Host ("  Property Setter  {0,-34} DELETED" -f $n) -ForegroundColor Green
        }
    }
    foreach ($n in $DeleteCustomFields) {
        if (Get-ErpDoc "Custom Field" $n) {
            Invoke-Erp Delete "/api/resource/$(Enc 'Custom Field')/$(Enc $n)" | Out-Null
            Write-Host ("  Custom Field     {0,-34} DELETED" -f $n) -ForegroundColor Green
        }
    }
    foreach ($n in $DeleteDocTypes) {
        if (Get-ErpDoc "DocType" $n) {
            try {
                Invoke-Erp Delete "/api/resource/$(Enc 'DocType')/$(Enc $n)" | Out-Null
                Write-Host ("  DocType          {0,-34} DELETED" -f $n) -ForegroundColor Green
            } catch {
                Write-Host ("  DocType          {0,-34} COULD NOT DELETE (rows may remain)" -f $n) -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy [-ConfirmDeletions] to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
