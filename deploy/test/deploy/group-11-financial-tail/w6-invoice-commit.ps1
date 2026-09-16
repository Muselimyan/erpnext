# ==============================================================
# W6 - Invoice commit action (Group 11 financial tail rebuild)
#
# No draft Sales Invoice is created automatically any more. The Invoice
# Preparation task shows a priced preview and the accountant commits it, which
# builds, values and SUBMITS the invoice in one action.
#
# What this fixes:
#   G1  A case where the client returned everything unused produced an Invoice
#       Preparation task whose gate demands a submitted invoice, while
#       create_invoice() had returned without creating one. The task could never
#       be completed by anyone, including an Administrator. There is now an
#       explicit "Nothing to Invoice" close action with a recorded reason.
#   G11 Dispatch Case.sales_invoice went stale on Cancel + Amend, because the
#       amendment is a new document with a new name. Sales Invoice.dispatch_case
#       is now the authoritative link and amendments carry it forward; the case
#       field is kept only as a convenience pointer that no logic reads.
#   G13 Invoices carried no VAT. Armenia Tax - Inmed (VAT 20% -> VAT - Inmed)
#       exists but has is_default = 0, so nothing ever applied it. The commit
#       action applies it and expands the tax rows explicitly -- setting
#       taxes_and_charges alone does not populate them.
#   G14 Invoices had no payment terms, so due_date equalled posting_date and
#       every receivables aging report was meaningless. Both existing templates
#       are prepayment terms with credit_days = 0, so a Net 30 term and
#       template are created here.
#   G15 hospital / doctor_name were never populated, so every dispatch invoice
#       was flagged by RPT - Data Quality - Missing Doctor or Hospital. They are
#       now taken from the Customer's own doctor_name / hospital / client_kind.
#
# Creates:
#   Payment Term          Net 30
#   Payment Terms Template Net 30
#   Custom Field          Sales Invoice.dispatch_case
#   Server Script         task_commit_invoice
#   Server Script         task_close_case_nothing_to_invoice
#
# Updates:
#   Task-after-save-dispatch-flow      (create_invoice removed; outstanding read
#                                       from the invoice, not grand_total minus
#                                       a stored prepaid figure)
#   Task-before-save-dispatch-gates    (invoice gate queries SI.dispatch_case)
#   Task-Product Work Area             (priced preview + both commit actions)
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

Write-Host "W6 invoice commit -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

# ── 1. Net 30 payment term + template ─────────────────────────────────
Write-Host "[1] Net 30 payment terms" -ForegroundColor Magenta
$termExists = Get-ErpDoc "Payment Term" "Net 30"
$tmplExists = Get-ErpDoc "Payment Terms Template" "Net 30"
if ($Mode -eq "Check") {
    Write-Host ("  Payment Term          Net 30  {0}" -f $(if ($termExists) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($termExists) { "DarkGray" } else { "Yellow" })
    Write-Host ("  Payment Terms Template Net 30  {0}" -f $(if ($tmplExists) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($tmplExists) { "DarkGray" } else { "Yellow" })
} else {
    if (-not $termExists) {
        Invoke-Erp Post "/api/resource/$(Enc 'Payment Term')" @{
            doctype = "Payment Term"; payment_term_name = "Net 30"
            due_date_based_on = "Day(s) after invoice date"; credit_days = 30
            invoice_portion = 100; description = "Payable within 30 days of the invoice date"
        } | Out-Null
        Write-Host "  Payment Term          Net 30  CREATED" -ForegroundColor Green
    } else { Write-Host "  Payment Term          Net 30  exists" -ForegroundColor DarkGray }
    if (-not $tmplExists) {
        Invoke-Erp Post "/api/resource/$(Enc 'Payment Terms Template')" @{
            doctype = "Payment Terms Template"; template_name = "Net 30"
            terms = @(@{ doctype = "Payment Terms Template Detail"; payment_term = "Net 30"
                    due_date_based_on = "Day(s) after invoice date"; credit_days = 30; invoice_portion = 100 })
        } | Out-Null
        Write-Host "  Payment Terms Template Net 30  CREATED" -ForegroundColor Green
    } else { Write-Host "  Payment Terms Template Net 30  exists" -ForegroundColor DarkGray }
}

# ── 2. Sales Invoice.dispatch_case ────────────────────────────────────
Write-Host ""
Write-Host "[2] Sales Invoice.dispatch_case" -ForegroundColor Magenta
$siField = Get-ErpDoc "Custom Field" "Sales Invoice-dispatch_case"
if ($Mode -eq "Check") {
    Write-Host ("  {0}" -f $(if ($siField) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($siField) { "DarkGray" } else { "Yellow" })
} elseif (-not $siField) {
    Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" @{
        doctype = "Custom Field"; dt = "Sales Invoice"; label = "Dispatch Case"
        fieldname = "dispatch_case"; fieldtype = "Link"; options = "Dispatch Case"
        insert_after = "customer"; read_only = 1; no_copy = 0
        description = "The operational case this invoice bills. Authoritative link; survives Cancel + Amend."
    } | Out-Null
    Write-Host "  CREATED" -ForegroundColor Green
} else { Write-Host "  exists" -ForegroundColor DarkGray }

# ── 3. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "task_commit_invoice"; File = "server\task_commit_invoice.py"; Type = "API" },
    @{ Name = "task_close_case_nothing_to_invoice"; File = "server\task_close_case_nothing_to_invoice.py"; Type = "API" },
    @{ Name = "Task-after-save-dispatch-flow"; File = "server\Task-after-save-dispatch-flow.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" }
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
    @{ Name = "Task-Product Work Area"; File = "client\Task-Product Work Area.js" }
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
            Write-Host ("  {0,-38} {1}" -f $c.Name, $state)
        } else {
            Write-Host ("  {0,-38} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-38} UPDATED" -f $c.Name) -ForegroundColor Green
        } else {
            Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = "Task"; view = "Form"; script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-38} CREATED" -f $c.Name) -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
