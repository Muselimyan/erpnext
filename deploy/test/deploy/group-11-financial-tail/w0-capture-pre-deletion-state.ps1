# ==============================================================
# W0 - Pre-deletion data capture (Group 11 financial tail rebuild)
#
# Read-only. Snapshots every field and child table that later
# workstreams delete, so W11 cleanup has a source and so the state
# is recoverable if a deletion needs to be reasoned about later.
#
# TEST ONLY. Reads credentials from deploy/test/export.ps1.
#
#   powershell -ExecutionPolicy Bypass -File deploy\test\deploy\group-11-financial-tail\w0-capture-pre-deletion-state.ps1
# ==============================================================

param()

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

Write-Host "W0 capture from $BaseUrl" -ForegroundColor Cyan

$OutDir = Join-Path $PSScriptRoot "snapshots"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Get-List {
    param([string]$DocType, [string[]]$Fields, [string]$Filters = $null, [string]$Parent = $null)
    # Build the JSON array by hand: ConvertTo-Json unwraps single-element
    # arrays into a bare string, which Frappe rejects.
    $FieldsJson = '["' + ($Fields -join '","') + '"]'
    $q = "/api/resource/$(Enc $DocType)?limit_page_length=0&fields=$(Enc $FieldsJson)"
    if ($Filters) { $q += "&filters=$(Enc $Filters)" }
    # Child (istable) doctypes return only `name` unless the parent doctype is
    # declared, so every child-table capture must pass -Parent.
    if ($Parent) { $q += "&parent=$(Enc $Parent)" }
    return (Invoke-RestMethod -Uri "$BaseUrl$q" -Headers $Headers -Method Get -TimeoutSec 180).data
}

function Get-Doc {
    param([string]$DocType, [string]$Name)
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 180).data
}

function Save-Snapshot {
    param([string]$FileName, $Data)
    $Path = Join-Path $OutDir $FileName
    $count = 0
    if ($Data -is [array]) { $count = $Data.Count } elseif ($null -ne $Data) { $count = 1 }
    # Force an array wrapper so an empty result still writes a valid "[]" file
    # rather than writing nothing at all.
    $Json = if ($count -eq 0) { "[]" } else { $Data | ConvertTo-Json -Depth 40 }
    Set-Content -Path $Path -Value $Json -Encoding UTF8
    Write-Host ("  {0,-46} {1,5} record(s)" -f $FileName, $count)
    return $count
}

$summary = [ordered]@{}
$summary.captured_at = (Get-Date).ToString("o")
$summary.target = $BaseUrl

# ── 1. Debt tasks, full documents including child tables ──────────────
Write-Host "Debt tasks (full docs with child tables)..." -ForegroundColor Yellow
$debtKinds = @("Debt Collection", "Debt Closure Approval", "Payment Received", "Debt Alert", "Distribute Payment")
$debtTaskDocs = @()
foreach ($kind in $debtKinds) {
    $names = Get-List "Task" @("name") ('{"task_kind":["=","' + $kind + '"]}')
    foreach ($row in $names) { $debtTaskDocs += (Get-Doc "Task" $row.name) }
}
$summary.debt_task_docs = Save-Snapshot "debt-task-docs.json" $debtTaskDocs

# ── 2. Dispatch Case financial fields ─────────────────────────────────
Write-Host "Dispatch Case financial fields..." -ForegroundColor Yellow
$dcFields = @("name", "status", "docstatus", "customer", "return_expected",
    "client_location_warehouse", "sales_invoice", "invoice_task",
    "prepaid_amount", "prepaid_payment_entry", "total_invoice_amount",
    "total_paid_amount", "outstanding_amount", "profit",
    "dispatch_stock_entry", "delivery_stock_entry", "consumption_stock_entry",
    "return_pickup_stock_entry", "return_receive_stock_entry", "restock_stock_entry")
$allCases = Get-List "Dispatch Case" $dcFields
$summary.dispatch_cases = Save-Snapshot "dispatch-case-financials.json" $allCases
$summary.dispatch_cases_submitted = @($allCases | Where-Object { $_.docstatus -eq 1 }).Count

# ── 3. Dispatch Cases carrying advance_payments rows (full docs) ───────
Write-Host "Dispatch Cases with advance payment rows..." -ForegroundColor Yellow
$advDocs = @()
$advCases = Get-List "Dispatch Case" @("name") '{"prepaid_amount":[">",0]}'
foreach ($row in $advCases) { $advDocs += (Get-Doc "Dispatch Case" $row.name) }
$summary.dispatch_cases_with_advances = Save-Snapshot "dispatch-case-advance-rows.json" $advDocs

# ── 4. Customer Payment Entries ───────────────────────────────────────
Write-Host "Customer Payment Entries..." -ForegroundColor Yellow
$peFields = @("name", "docstatus", "posting_date", "party_type", "party", "payment_type",
    "paid_amount", "received_amount", "unallocated_amount", "mode_of_payment",
    "paid_to", "paid_from", "reference_no", "reference_date", "owner", "creation")
$summary.payment_entries = Save-Snapshot "payment-entries.json" (Get-List "Payment Entry" $peFields '{"party_type":["=","Customer"]}')

# ── 5. Payment Entry References ───────────────────────────────────────
Write-Host "Payment Entry references..." -ForegroundColor Yellow
$summary.payment_entry_references = Save-Snapshot "payment-entry-references.json" (Get-List "Payment Entry Reference" @("name", "parent", "reference_doctype", "reference_name", "allocated_amount", "outstanding_amount", "total_amount"))

# ── 6. Sales Invoices ─────────────────────────────────────────────────
Write-Host "Sales Invoices..." -ForegroundColor Yellow
$siFields = @("name", "docstatus", "customer", "posting_date", "due_date", "currency",
    "net_total", "total_taxes_and_charges", "grand_total", "outstanding_amount",
    "taxes_and_charges", "payment_terms_template", "update_stock", "is_return",
    "amended_from", "hospital", "doctor_name", "owner", "creation")
$summary.sales_invoices = Save-Snapshot "sales-invoices.json" (Get-List "Sales Invoice" $siFields)

# ── 7. Dispatch Case Item rows ────────────────────────────────────────
# NOTE: `unit_price` and `discount_pct` are permlevel 2 (set via Property
# Setter) and are therefore stripped from REST responses. The W7 blast-radius
# metric below was measured directly against the database and is recorded as a
# constant; it is a planning diagnostic, not recoverable state, so it is not
# re-derived on every run.
Write-Host "Dispatch Case Item rows (quantities; prices are permlevel-restricted)..." -ForegroundColor Yellow
$dciFields = @("name", "parent", "item_code", "dispatched_qty", "used_qty",
    "returned_qty", "lost_damaged_qty", "batch_no")
$allItems = Get-List "Dispatch Case Item" $dciFields -Parent "Dispatch Case"
$summary.dc_items_total = @($allItems).Count
Save-Snapshot "dc-items.json" $allItems | Out-Null

$summary.w7_blast_radius = [ordered]@{
    note                                = "Measured via direct DB query; unit_price is permlevel 2 and not exposed over REST."
    measured_at                         = "2026-09-16"
    rows_on_submitted_cases             = 1292
    zero_price_rows                     = 840
    submitted_cases_with_rows           = 553
    submitted_cases_with_any_zero_price = 103
}

# ── 8. Schema objects being deleted ───────────────────────────────────
Write-Host "Schema objects slated for deletion..." -ForegroundColor Yellow
$schemaTargets = [ordered]@{}
$taskFieldsToDelete = @("open_invoices", "payment_history", "total_outstanding",
    "available_advance_credit", "custom_total_amount_paid")
$dcFieldsToDelete = @("prepaid_amount", "prepaid_payment_entry", "advance_payments",
    "total_paid_amount", "outstanding_amount", "total_invoice_amount", "sales_invoice")
$schemaTargets.task_custom_fields = Get-List "Custom Field" @("name", "dt", "fieldname", "fieldtype", "options", "insert_after", "allow_on_submit", "permlevel", "read_only") '{"dt":["=","Task"]}'
$schemaTargets.dispatch_case_custom_fields = Get-List "Custom Field" @("name", "dt", "fieldname", "fieldtype", "options", "insert_after", "allow_on_submit", "permlevel", "read_only") '{"dt":["=","Dispatch Case"]}'
$schemaTargets.task_property_setters = Get-List "Property Setter" @("name", "doc_type", "field_name", "property", "value") '{"doc_type":["=","Task"]}'
$schemaTargets.dispatch_case_property_setters = Get-List "Property Setter" @("name", "doc_type", "field_name", "property", "value") '{"doc_type":["=","Dispatch Case"]}'
$schemaTargets.planned_task_field_deletions = $taskFieldsToDelete
$schemaTargets.planned_dispatch_case_field_deletions = $dcFieldsToDelete
$schemaTargets.planned_child_doctype_deletions = @("Debt Collection Invoice", "Debt Collection Payment", "Dispatch Case Advance Payment")
Save-Snapshot "schema-deletion-targets.json" $schemaTargets | Out-Null

# ── 9. Access-control scripts being replaced ──────────────────────────
Write-Host "Access-control server scripts (pre-W1 bodies)..." -ForegroundColor Yellow
$acScripts = @("Task-before-save-dispatch-gates", "Task-before-save-policy",
    "Task-before-save-lock-unaccepted", "Task-before-save-lock-completed",
    "Dispatch-Case-before-save-lock-submitted", "Task-before-save-payment-recording")
$acDocs = @()
foreach ($n in $acScripts) {
    try { $acDocs += (Get-Doc "Server Script" $n) } catch { Write-Host "  (missing: $n)" -ForegroundColor DarkGray }
}
Save-Snapshot "server-scripts-pre-w1.json" $acDocs | Out-Null

# ── Summary ───────────────────────────────────────────────────────────
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutDir "_capture-summary.json") -Encoding UTF8

Write-Host ""
Write-Host "Snapshots written to $OutDir" -ForegroundColor Green
$summary | ConvertTo-Json -Depth 10
Write-Host ""
Write-Host "Next: run deploy\test\export.ps1 to capture the full schema tree as the restore reference." -ForegroundColor Cyan
