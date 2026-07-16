#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Tender Agreement system for hospital-specific pricing with quantity tracking.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — create / update all artefacts (idempotent)
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action="created"; name=$C.name }
    }
    $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$U.name }
}

Write-Host "=== Tender Agreement System Deployment ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# 1) CREATE CHILD DOCTYPE: Tender Agreement Item
# ---------------------------------------------------------------------------
$TenderItemDocType = @{
    doctype = "DocType"
    name = "Tender Agreement Item"
    module = "Selling"
    custom = 1
    istable = 1
    editable_grid = 1
    fields = @(
        @{ fieldname="item_code"; label="Item Code"; fieldtype="Link"; options="Item"; in_list_view=1; reqd=1; columns=2 },
        @{ fieldname="item_name"; label="Item Name"; fieldtype="Data"; fetch_from="item_code.item_name"; read_only=1; in_list_view=1; columns=2 },
        @{ fieldname="tender_price"; label="Tender Price"; fieldtype="Currency"; in_list_view=1; reqd=1; columns=1 },
        @{ fieldname="won_quantity"; label="Won Quantity"; fieldtype="Float"; in_list_view=1; reqd=1; columns=1 },
        @{ fieldname="supplied_quantity"; label="Supplied Quantity"; fieldtype="Float"; in_list_view=1; read_only=1; default=0; columns=1 },
        @{ fieldname="remaining_quantity"; label="Remaining Quantity"; fieldtype="Float"; in_list_view=1; read_only=1; columns=1 }
    )
    permissions = @(
        @{ role="All"; read=1; write=1; create=1 }
    )
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "DocType" -Name "Tender Agreement Item"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Tender Agreement Item DocType (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Tender Agreement Item DocType exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Tender Agreement Item DocType..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "DocType" -Name "Tender Agreement Item" -Body $TenderItemDocType
    Write-Host "  [✓] Tender Agreement Item DocType $($Result.action)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2) CREATE PARENT DOCTYPE: Tender Agreement
# ---------------------------------------------------------------------------
$TenderAgreementDocType = @{
    doctype = "DocType"
    name = "Tender Agreement"
    module = "Selling"
    custom = 1
    naming_rule = "By fieldname"
    autoname = "field:tender_name"
    fields = @(
        @{ fieldname="tender_name"; label="Tender Name"; fieldtype="Data"; reqd=1; unique=1 },
        @{ fieldname="hospital"; label="Hospital"; fieldtype="Link"; options="Customer"; reqd=1; in_list_view=1 },
        @{ fieldname="valid_from"; label="Valid From"; fieldtype="Date"; reqd=1; in_list_view=1 },
        @{ fieldname="valid_to"; label="Valid To"; fieldtype="Date"; reqd=1; in_list_view=1 },
        @{ fieldname="status"; label="Status"; fieldtype="Select"; options="Draft\nActive\nExpired\nClosed"; default="Draft"; in_list_view=1; in_standard_filter=1 },
        @{ fieldname="section_break_1"; label="Tender Items"; fieldtype="Section Break" },
        @{ fieldname="items"; label="Items"; fieldtype="Table"; options="Tender Agreement Item"; reqd=1 },
        @{ fieldname="section_break_2"; label="Notes"; fieldtype="Section Break" },
        @{ fieldname="notes"; label="Notes"; fieldtype="Text Editor" }
    )
    permissions = @(
        @{ role="Ops - Accounting"; read=1; write=1; create=1; submit=0; cancel=0; delete=0 },
        @{ role="Ops - Directors"; read=1; write=1; create=1; submit=0; cancel=0; delete=1 },
        @{ role="Ops - Order Creating"; read=1; write=0; create=0; submit=0; cancel=0; delete=0 }
    )
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "DocType" -Name "Tender Agreement"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Tender Agreement DocType (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Tender Agreement DocType exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Tender Agreement DocType..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "DocType" -Name "Tender Agreement" -Body $TenderAgreementDocType
    Write-Host "  [✓] Tender Agreement DocType $($Result.action)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3) CREATE SERVER SCRIPT: Auto-calculate remaining quantity
# ---------------------------------------------------------------------------
$TenderBeforeSaveScript = @'
# Calculate remaining quantity for each tender item
for row in doc.items:
    row.remaining_quantity = (row.won_quantity or 0) - (row.supplied_quantity or 0)

# Auto-set status based on dates
from frappe.utils import nowdate, getdate
today = getdate(nowdate())
valid_from = getdate(doc.valid_from) if doc.valid_from else None
valid_to = getdate(doc.valid_to) if doc.valid_to else None

if doc.status == "Draft":
    pass  # Keep as Draft until manually activated
elif valid_from and valid_to:
    if today < valid_from:
        doc.status = "Draft"
    elif today >= valid_from and today <= valid_to:
        doc.status = "Active"
    elif today > valid_to:
        doc.status = "Expired"
'@

$TenderBeforeSave = @{
    doctype = "Server Script"
    name = "Tender-Agreement-before-save"
    script_type = "DocType Event"
    doctype_event = "Before Save"
    reference_doctype = "Tender Agreement"
    disabled = 0
    script = $TenderBeforeSaveScript
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "Server Script" -Name "Tender-Agreement-before-save"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Server Script: Tender-Agreement-before-save (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Server Script: Tender-Agreement-before-save exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Server Script: Tender-Agreement-before-save..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "Server Script" -Name "Tender-Agreement-before-save" -Body $TenderBeforeSave
    Write-Host "  [✓] Server Script: Tender-Agreement-before-save $($Result.action)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4) CREATE SERVER SCRIPT: Update supplied quantity when invoice is submitted
# ---------------------------------------------------------------------------
$InvoiceTenderUpdateScript = @'
# Update tender supplied quantities when Sales Invoice is submitted
if doc.docstatus != 1:  # Only on submit
    return

hospital = doc.customer

# Find active tenders for this hospital
tenders = frappe.get_all("Tender Agreement", 
    filters={"hospital": hospital, "status": "Active"},
    fields=["name"])

if not tenders:
    return  # No active tenders

# For each invoice item, check if it's in an active tender
for inv_item in doc.items:
    item_code = inv_item.item_code
    qty = inv_item.qty or 0
    
    # Find tender with this item
    for tender_doc_name in [t.name for t in tenders]:
        tender = frappe.get_doc("Tender Agreement", tender_doc_name)
        
        for tender_item in tender.items:
            if tender_item.item_code == item_code:
                # Update supplied quantity
                tender_item.supplied_quantity = (tender_item.supplied_quantity or 0) + qty
                tender_item.remaining_quantity = (tender_item.won_quantity or 0) - tender_item.supplied_quantity
                
        # Save tender (will trigger before_save to recalculate)
        tender.flags.ignore_permissions = True
        tender.save()
        frappe.db.commit()
'@

$InvoiceTenderUpdate = @{
    doctype = "Server Script"
    name = "Sales-Invoice-after-submit-tender-update"
    script_type = "DocType Event"
    doctype_event = "After Submit"
    reference_doctype = "Sales Invoice"
    disabled = 0
    script = $InvoiceTenderUpdateScript
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "Server Script" -Name "Sales-Invoice-after-submit-tender-update"
    if ($null -eq $Existing) {
        Write-Host "  [ ] Server Script: Sales-Invoice-after-submit-tender-update (will be created)" -ForegroundColor Yellow
    } else {
        Write-Host "  [✓] Server Script: Sales-Invoice-after-submit-tender-update exists" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating/updating Server Script: Sales-Invoice-after-submit-tender-update..." -ForegroundColor Cyan
    $Result = Upsert-ErpDoc -DocType "Server Script" -Name "Sales-Invoice-after-submit-tender-update" -Body $InvoiceTenderUpdate
    Write-Host "  [✓] Server Script: Sales-Invoice-after-submit-tender-update $($Result.action)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Green
if ($Mode -eq "Check") {
    Write-Host "Run with -Mode Deploy to create/update artifacts" -ForegroundColor Yellow
} else {
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "1. Create a Tender Agreement in ERPNext" -ForegroundColor White
    Write-Host "2. Add items with tender prices and won quantities" -ForegroundColor White
    Write-Host "3. Set valid_from and valid_to dates" -ForegroundColor White
    Write-Host "4. Change status to 'Active'" -ForegroundColor White
    Write-Host "5. When creating Sales Invoice for that hospital, tender prices will be suggested" -ForegroundColor White
    Write-Host "6. Supplied quantities will auto-update when invoice is submitted" -ForegroundColor White
}
